export class ApiError extends Error {
  constructor(status, message, details) {
    super(message);
    this.status = status;
    this.details = details;
  }
}

export function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
    },
  });
}

export async function readJson(request) {
  const text = await request.text();
  if (!text.trim()) {
    return {};
  }
  try {
    const value = JSON.parse(text);
    return value && typeof value === "object" ? value : {};
  } catch {
    throw new ApiError(400, "请求体不是有效的 JSON");
  }
}

export function requireAccess(request, env) {
  if (`${env.CLOUDFLARE_ACCESS_REQUIRED ?? "true"}`.toLowerCase() === "false") {
    return;
  }
  const assertion = request.headers.get("cf-access-jwt-assertion");
  const email = request.headers.get("cf-access-authenticated-user-email");
  if (!assertion && !email) {
    throw new ApiError(401, "需要通过 Cloudflare Access 登录后访问");
  }
}

export function requireText(env, names) {
  for (const name of names) {
    const value = env[name];
    if (typeof value === "string" && value.trim()) {
      return value.trim();
    }
  }
  throw new ApiError(500, `Cloudflare 环境变量未配置：${names.join(" 或 ")}`);
}

export function asInt(value, fallback = 0) {
  const parsed = Number.parseInt(`${value ?? ""}`, 10);
  return Number.isFinite(parsed) ? parsed : fallback;
}

export function asNumber(value, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

export function uniqueStrings(values) {
  return [
    ...new Set(
      (Array.isArray(values) ? values : [])
        .map((value) => `${value ?? ""}`.trim())
        .filter(Boolean),
    ),
  ];
}

export function errorResponse(error) {
  if (error instanceof ApiError) {
    return json(
      { success: false, message: error.message, details: error.details ?? null },
      error.status,
    );
  }
  console.error("Unhandled Cloudflare API error", error);
  return json(
    {
      success: false,
      message: error instanceof Error ? error.message : `${error}`,
    },
    500,
  );
}
