import assert from "node:assert/strict";
import { afterEach, test } from "node:test";

import { onRequest } from "../functions/api/[[path]].js";

const originalFetch = globalThis.fetch;

afterEach(() => {
  globalThis.fetch = originalFetch;
});

const accessHeaders = {
  "Cf-Access-Authenticated-User-Email": "hr@example.com",
};

function context(path, { method = "GET", body, headers = {} } = {}) {
  return {
    request: new Request(`https://hr.example.com/api/${path}`, {
      method,
      headers: {
        ...accessHeaders,
        ...(body ? { "Content-Type": "application/json" } : {}),
        ...headers,
      },
      body: body ? JSON.stringify(body) : undefined,
    }),
    env: {
      WECOM_CORP_ID: "ww-test",
      WECOM_AGENT: "1000021",
      WECOM_SECRET: "wecom-secret",
      WECOM_CONTACT_SECRET: "contact-secret",
      DB_HOST: "gateway.example.com",
      DB_USERNAME: "db-user",
      DB_PASSWORD: "db-password",
      DB_DATABASE: "tospino_hr",
    },
  };
}

test("requires Cloudflare Access before serving production configuration", async () => {
  const response = await onRequest(
    context("runtime-config", { headers: { "Cf-Access-Authenticated-User-Email": "" } }),
  );
  assert.equal(response.status, 401);
});

test("returns only public production configuration", async () => {
  const response = await onRequest(context("runtime-config"));
  const body = await response.json();

  assert.equal(response.status, 200);
  assert.equal(body.wecom.corpId, "ww-test");
  assert.equal(body.wecom.agentId, "1000021");
  assert.equal(body.wecom.configured, true);
  assert.equal(body.wecom.contactConfigured, true);
  assert.equal(body.database.configured, true);
  assert.equal(JSON.stringify(body).includes("wecom-secret"), false);
  assert.equal(JSON.stringify(body).includes("db-password"), false);
});

test("proxies WeCom check-in data using Cloudflare secrets", async () => {
  const calls = [];
  globalThis.fetch = async (url, init) => {
    calls.push({ url: `${url}`, init });
    if (`${url}`.includes("/cgi-bin/gettoken")) {
      return Response.json({
        errcode: 0,
        access_token: "access-token",
        expires_in: 7200,
      });
    }
    return Response.json({
      errcode: 0,
      errmsg: "ok",
      checkindata: [{
        userid: "zhangsan",
        checkin_time: 1700000000,
        checkin_type: "上班打卡",
        exception_type: "",
      }],
    });
  };

  const response = await onRequest(
    context("wecom", {
      method: "POST",
      body: {
        action: "checkin",
        payload: {
          data_type: 3,
          start_time: 1699990000,
          end_time: 1700010000,
          user_ids: ["zhangsan"],
        },
      },
    }),
  );
  const body = await response.json();

  assert.equal(response.status, 200);
  assert.equal(body.errcode, 0);
  assert.equal(body.checkindata[0].userid, "zhangsan");
  assert.equal(calls.length, 2);
  assert.match(calls[0].url, /corpsecret=wecom-secret/);
  assert.match(calls[1].url, /access_token=access-token/);
  assert.equal(JSON.parse(calls[1].init.body).opencheckindatatype, 3);
});

test("rejects database access when production secrets are missing", async () => {
  const requestContext = context("db", {
    method: "POST",
    body: { action: "ping", payload: {} },
  });
  delete requestContext.env.DB_PASSWORD;
  const response = await onRequest(requestContext);
  const body = await response.json();

  assert.equal(response.status, 500);
  assert.match(body.message, /DB_PASSWORD/);
});
