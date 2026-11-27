import {
  ApiError,
  errorResponse,
  json,
  readJson,
  requireAccess,
} from "../_lib/common.js";
import { handleDatabase } from "../_lib/database.js";
import { handleWeCom } from "../_lib/wecom.js";

function configured(env, names) {
  return names.every((name) => {
    const value = env[name];
    return typeof value === "string" && value.trim().length > 0;
  });
}

function runtimeConfig(env) {
  const corpId = `${env.WECOM_CORP_ID ?? env.WECOM_CORP ?? ""}`.trim();
  const agentId = `${env.WECOM_AGENT_ID ?? env.WECOM_AGENT ?? ""}`.trim();
  const wecomConfigured = Boolean(
    corpId &&
      agentId &&
      configured(env, ["WECOM_SECRET"]),
  );
  const databaseConfigured = configured(env, [
    "DB_HOST",
    "DB_USERNAME",
    "DB_PASSWORD",
    "DB_DATABASE",
  ]);
  return {
    cloudflareProxy: true,
    wecom: {
      corpId,
      agentId,
      configured: wecomConfigured,
      contactConfigured: Boolean(
        corpId && configured(env, ["WECOM_CONTACT_SECRET"]),
      ),
    },
    database: {
      host: `${env.DB_HOST ?? ""}`.trim(),
      port: `${env.DB_PORT ?? "4000"}`.trim(),
      database: `${env.DB_DATABASE ?? ""}`.trim(),
      configured: databaseConfigured,
    },
  };
}

function apiPath(request) {
  const pathname = new URL(request.url).pathname;
  return pathname.replace(/^\/api\/?/, "").replace(/\/+$/, "");
}

async function route({ request, env }) {
  requireAccess(request, env);
  const path = apiPath(request);

  if (request.method === "GET" && (path === "health" || path === "runtime-config")) {
    if (path === "health") {
      return json({ ok: true, cloudflareProxy: true });
    }
    return json(runtimeConfig(env));
  }

  if (request.method === "POST" && path === "wecom") {
    const body = await readJson(request);
    const action = `${body.action ?? ""}`.trim();
    if (!action) {
      throw new ApiError(400, "缺少 action");
    }
    return json(await handleWeCom(env, action, body.payload ?? {}));
  }

  if (request.method === "POST" && path === "db") {
    const body = await readJson(request);
    const action = `${body.action ?? ""}`.trim();
    if (!action) {
      throw new ApiError(400, "缺少 action");
    }
    return json(await handleDatabase(env, action, body.payload ?? {}));
  }

  throw new ApiError(404, "API 接口不存在");
}

export async function onRequest(context) {
  try {
    return await route(context);
  } catch (error) {
    return errorResponse(error);
  }
}
