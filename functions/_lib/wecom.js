import {
  ApiError,
  asInt,
  requireText,
  uniqueStrings,
} from "./common.js";

const API_BASE = "https://qyapi.weixin.qq.com";
const TOKEN_ERROR_CODES = new Set([40014, 42001]);
const tokenCache = new Map();

function corpId(env) {
  return requireText(env, ["WECOM_CORP_ID", "WECOM_CORP"]);
}

function agentId(env) {
  return requireText(env, ["WECOM_AGENT_ID", "WECOM_AGENT"]);
}

function applicationSecret(env) {
  return requireText(env, ["WECOM_SECRET"]);
}

function contactSecret(env) {
  const value = env.WECOM_CONTACT_SECRET;
  return typeof value === "string" ? value.trim() : "";
}

async function jsonFetch(url, init) {
  const response = await fetch(url, init);
  const text = await response.text();
  let body;
  try {
    body = JSON.parse(text);
  } catch {
    throw new ApiError(
      response.ok ? 502 : response.status,
      `企业微信返回了非 JSON 响应（HTTP ${response.status}）`,
      text.slice(0, 500),
    );
  }
  if (!response.ok) {
    throw new ApiError(
      response.status,
      body?.errmsg || `企业微信请求失败（HTTP ${response.status}）`,
      body,
    );
  }
  return body;
}

async function getToken(env, contact = false) {
  const corp = corpId(env);
  const secret = contact ? contactSecret(env) : applicationSecret(env);
  if (!secret) {
    throw new ApiError(500, "WECOM_CONTACT_SECRET 未配置");
  }
  const cacheKey = `${corp}:${contact ? "contact" : "app"}`;
  const cached = tokenCache.get(cacheKey);
  if (cached && cached.expiresAt > Date.now() + 60_000) {
    return cached.token;
  }

  const url = new URL("/cgi-bin/gettoken", API_BASE);
  url.searchParams.set("corpid", corp);
  url.searchParams.set("corpsecret", secret);
  const data = await jsonFetch(url);
  if (asInt(data.errcode) !== 0 || !data.access_token) {
    throw new ApiError(
      502,
      data.errmsg || "企业微信未返回 access_token",
      data,
    );
  }
  tokenCache.set(cacheKey, {
    token: `${data.access_token}`,
    expiresAt: Date.now() + Math.max(asInt(data.expires_in, 7200), 300) * 1000,
  });
  return `${data.access_token}`;
}

async function requestWithToken(env, { path, method = "GET", body, contact = false }) {
  let token = await getToken(env, contact);
  for (let attempt = 0; attempt < 2; attempt++) {
    const url = new URL(path, API_BASE);
    url.searchParams.set("access_token", token);
    const data = await jsonFetch(url, {
      method,
      headers:
        body === undefined
          ? undefined
          : { "content-type": "application/json; charset=utf-8" },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    if (!TOKEN_ERROR_CODES.has(asInt(data.errcode))) {
      return data;
    }
    tokenCache.delete(
      `${corpId(env)}:${contact ? "contact" : "app"}`,
    );
    token = await getToken(env, contact);
  }
  return {
    errcode: 42001,
    errmsg: "企业微信凭证刷新后仍不可用",
  };
}

function memberMapToArray(userDepartments) {
  return [...userDepartments.entries()]
    .map(([userid, departments]) => ({
      userid,
      department: [...departments].sort((a, b) => a - b),
    }))
    .sort((a, b) => a.userid.localeCompare(b.userid));
}

async function contactMembers(env, limit) {
  const userDepartments = new Map();
  const visited = new Set();
  let cursor = "";
  for (;;) {
    const body = { limit };
    if (cursor) {
      body.cursor = cursor;
    }
    const data = await requestWithToken(env, {
      path: "/cgi-bin/user/list_id",
      method: "POST",
      body,
      contact: true,
    });
    if (asInt(data.errcode) !== 0) {
      return data;
    }
    if (!Array.isArray(data.dept_user)) {
      throw new ApiError(502, "企业微信 dept_user 不是数组");
    }
    for (const item of data.dept_user) {
      const userId = `${item?.userid ?? ""}`.trim();
      if (!userId) {
        continue;
      }
      const departments = userDepartments.get(userId) ?? new Set();
      const departmentId = asInt(item.department, -1);
      if (departmentId >= 0) {
        departments.add(departmentId);
      }
      userDepartments.set(userId, departments);
    }
    const nextCursor = `${data.next_cursor ?? ""}`.trim();
    if (!nextCursor) {
      break;
    }
    if (visited.has(nextCursor)) {
      throw new ApiError(502, "企业微信通讯录分页游标重复");
    }
    visited.add(nextCursor);
    cursor = nextCursor;
  }
  return { errcode: 0, members: memberMapToArray(userDepartments) };
}

async function applicationVisibleMembers(env) {
  const departmentData = await requestWithToken(env, {
    path: "/cgi-bin/department/list",
  });
  if (asInt(departmentData.errcode) !== 0) {
    return departmentData;
  }
  if (!Array.isArray(departmentData.department)) {
    throw new ApiError(502, "企业微信 department 不是数组");
  }
  const departmentIds = [
    ...new Set(
      departmentData.department
        .map((item) => asInt(item?.id, -1))
        .filter((value) => value >= 0),
    ),
  ].sort((a, b) => a - b);
  const userDepartments = new Map();
  for (const departmentId of departmentIds) {
    const path = `/cgi-bin/user/simplelist?department_id=${departmentId}`;
    const userData = await requestWithToken(env, { path });
    if (asInt(userData.errcode) !== 0) {
      return userData;
    }
    if (!Array.isArray(userData.userlist)) {
      throw new ApiError(502, "企业微信 userlist 不是数组");
    }
    for (const user of userData.userlist) {
      const userId = `${user?.userid ?? ""}`.trim();
      if (!userId) {
        continue;
      }
      const departments = userDepartments.get(userId) ?? new Set();
      if (Array.isArray(user.department)) {
        for (const value of user.department) {
          const id = asInt(value, -1);
          if (id >= 0) {
            departments.add(id);
          }
        }
      }
      if (!departments.size) {
        departments.add(departmentId);
      }
      userDepartments.set(userId, departments);
    }
  }
  return { errcode: 0, members: memberMapToArray(userDepartments) };
}

async function memberList(env, payload) {
  const limit = Math.min(Math.max(asInt(payload.limit, 10000), 1), 10000);
  if (contactSecret(env)) {
    const contactResult = await contactMembers(env, limit);
    if (asInt(contactResult.errcode) !== 48002) {
      return contactResult;
    }
  }
  return applicationVisibleMembers(env);
}

export async function handleWeCom(env, action, payload = {}) {
  try {
    agentId(env);
    corpId(env);
    if (action === "check_connection") {
      await getToken(env);
      return { errcode: 0, errmsg: "ok" };
    }
    if (action === "checkin") {
      return await requestWithToken(env, {
        path: "/cgi-bin/checkin/getcheckindata",
        method: "POST",
        body: {
          opencheckindatatype: asInt(payload.data_type, 3),
          starttime: asInt(payload.start_time),
          endtime: asInt(payload.end_time),
          useridlist: uniqueStrings(payload.user_ids),
        },
      });
    }
    if (action === "monthly_report") {
      return await requestWithToken(env, {
        path: "/cgi-bin/checkin/getcheckin_monthdata",
        method: "POST",
        body: {
          starttime: asInt(payload.start_time),
          endtime: asInt(payload.end_time),
          useridlist: uniqueStrings(payload.user_ids),
        },
      });
    }
    if (action === "user_by_mobile") {
      return await requestWithToken(env, {
        path: "/cgi-bin/user/getuserid",
        method: "POST",
        body: { mobile: `${payload.mobile ?? ""}`.trim() },
      });
    }
    if (action === "user_by_email") {
      return await requestWithToken(env, {
        path: "/cgi-bin/user/get_userid_by_email",
        method: "POST",
        body: {
          email: `${payload.email ?? ""}`.trim(),
          email_type: asInt(payload.email_type, 1),
        },
      });
    }
    if (action === "member_list") {
      return await memberList(env, payload);
    }
    throw new ApiError(400, `不支持的企业微信操作：${action}`);
  } catch (error) {
    if (error instanceof ApiError) {
      return { errcode: 500, errmsg: error.message, details: error.details };
    }
    throw error;
  }
}
