import { connect } from "@tidbcloud/serverless";

import {
  ApiError,
  asInt,
  asNumber,
  requireText,
  uniqueStrings,
} from "./common.js";

const schemaCache = new Set();

function normalizedHost(value) {
  return requireText({ DB_HOST: value }, ["DB_HOST"])
    .replace(/^https?:\/\//i, "")
    .replace(/\/.*$/, "")
    .replace(/:\d+$/, "");
}

function databaseConnection(env) {
  const host = normalizedHost(env.DB_HOST);
  const username = requireText(env, ["DB_USERNAME"]);
  const password = requireText(env, ["DB_PASSWORD"]);
  const database = requireText(env, ["DB_DATABASE"]);
  return {
    connection: connect({
      host,
      username,
      password,
      database,
      fullResult: true,
    }),
    key: `${host}/${database}/${username}`,
  };
}

async function execute(connection, sql, args = []) {
  return connection.execute(sql, args);
}

async function ensureSchema(env, connection, key) {
  if (schemaCache.has(key)) {
    return;
  }
  const statements = [
    `CREATE TABLE IF NOT EXISTS checkin_records (
      source_key VARCHAR(512) PRIMARY KEY,
      user_id VARCHAR(191) NOT NULL,
      record_date DATE NOT NULL,
      checkin_at BIGINT NOT NULL,
      checkin_type VARCHAR(64) NOT NULL DEFAULT '',
      exception_type VARCHAR(255) NOT NULL DEFAULT '',
      group_name VARCHAR(255) NOT NULL DEFAULT '',
      group_id BIGINT NULL,
      schedule_id BIGINT NULL,
      timeline_id BIGINT NULL,
      location_title VARCHAR(512) NOT NULL DEFAULT '',
      location_detail VARCHAR(1024) NOT NULL DEFAULT '',
      wifi_name VARCHAR(255) NOT NULL DEFAULT '',
      wifi_mac VARCHAR(128) NOT NULL DEFAULT '',
      notes TEXT NULL,
      device_id VARCHAR(255) NOT NULL DEFAULT '',
      schedule_checkin_at BIGINT NULL,
      latitude DOUBLE NULL,
      longitude DOUBLE NULL,
      media_ids JSON NULL,
      synced_at BIGINT NOT NULL,
      INDEX idx_checkin_user_date (user_id, record_date),
      INDEX idx_checkin_time (checkin_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
    `CREATE TABLE IF NOT EXISTS sync_runs (
      id BIGINT PRIMARY KEY AUTO_INCREMENT,
      started_at BIGINT NOT NULL,
      completed_at BIGINT NULL,
      first_month VARCHAR(16) NOT NULL,
      last_month VARCHAR(16) NOT NULL,
      user_count INT NOT NULL,
      sync_mode VARCHAR(16) NOT NULL,
      status VARCHAR(16) NOT NULL,
      record_count INT NOT NULL DEFAULT 0,
      report_count INT NOT NULL DEFAULT 0,
      error_message TEXT NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
    `CREATE TABLE IF NOT EXISTS sync_windows (
      source_key VARCHAR(255) PRIMARY KEY,
      user_id VARCHAR(191) NOT NULL,
      period_start BIGINT NOT NULL,
      period_end_exclusive BIGINT NOT NULL,
      synced_at BIGINT NOT NULL,
      INDEX idx_sync_window_period (period_start, period_end_exclusive)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
    `CREATE TABLE IF NOT EXISTS monthly_report_snapshots (
      source_key VARCHAR(512) PRIMARY KEY,
      user_id VARCHAR(191) NOT NULL,
      year INT NOT NULL,
      period_start BIGINT NOT NULL,
      period_end_exclusive BIGINT NOT NULL,
      report_json TEXT NOT NULL,
      synced_at BIGINT NOT NULL,
      INDEX idx_report_year_user (year, user_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
  ];
  for (const statement of statements) {
    await execute(connection, statement);
  }
  schemaCache.add(key);
}

function placeholders(values) {
  return values.map(() => "?").join(", ");
}

function userClause(userIds, column = "user_id") {
  return userIds.length ? ` AND ${column} IN (${placeholders(userIds)})` : "";
}

function dateKey(value) {
  const date = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(date.getTime())) {
    return `${value ?? ""}`.slice(0, 10);
  }
  return date.toISOString().slice(0, 10);
}

function monthKey(value) {
  return dateKey(value).slice(0, 7);
}

function rowRecord(row) {
  let mediaIds = row.media_ids;
  if (typeof mediaIds === "string") {
    try {
      mediaIds = JSON.parse(mediaIds);
    } catch {
      mediaIds = [];
    }
  }
  const checkinSeconds = Math.floor(asNumber(row.checkin_at) / 1000);
  const scheduleSeconds = row.schedule_checkin_at == null
    ? null
    : Math.floor(asNumber(row.schedule_checkin_at) / 1000);
  return {
    userid: `${row.user_id ?? ""}`,
    groupname: `${row.group_name ?? ""}`,
    checkin_type: `${row.checkin_type ?? ""}`,
    exception_type: `${row.exception_type ?? ""}`,
    checkin_time: checkinSeconds,
    location_title: `${row.location_title ?? ""}`,
    location_detail: `${row.location_detail ?? ""}`,
    wifiname: `${row.wifi_name ?? ""}`,
    notes: `${row.notes ?? ""}`,
    wifimac: `${row.wifi_mac ?? ""}`,
    mediaids: Array.isArray(mediaIds) ? mediaIds.map(String) : [],
    lat: row.latitude == null ? null : asNumber(row.latitude),
    lng: row.longitude == null ? null : asNumber(row.longitude),
    deviceid: `${row.device_id ?? ""}`,
    sch_checkin_time: scheduleSeconds,
    groupid: row.group_id == null ? null : asInt(row.group_id),
    schedule_id: row.schedule_id == null ? null : asInt(row.schedule_id),
    timeline_id: row.timeline_id == null ? null : asInt(row.timeline_id),
  };
}

function recordArgs(record, syncedAt) {
  return [
    `${record.source_key ?? ""}`,
    `${record.user_id ?? ""}`,
    `${record.record_date ?? ""}`,
    asInt(record.checkin_at),
    `${record.checkin_type ?? ""}`,
    `${record.exception_type ?? ""}`,
    `${record.group_name ?? ""}`,
    record.group_id ?? null,
    record.schedule_id ?? null,
    record.timeline_id ?? null,
    `${record.location_title ?? ""}`,
    `${record.location_detail ?? ""}`,
    `${record.wifi_name ?? ""}`,
    `${record.wifi_mac ?? ""}`,
    `${record.notes ?? ""}`,
    `${record.device_id ?? ""}`,
    record.schedule_checkin_at ?? null,
    record.latitude ?? null,
    record.longitude ?? null,
    JSON.stringify(Array.isArray(record.media_ids) ? record.media_ids : []),
    syncedAt,
  ];
}

const recordColumns = [
  "source_key",
  "user_id",
  "record_date",
  "checkin_at",
  "checkin_type",
  "exception_type",
  "group_name",
  "group_id",
  "schedule_id",
  "timeline_id",
  "location_title",
  "location_detail",
  "wifi_name",
  "wifi_mac",
  "notes",
  "device_id",
  "schedule_checkin_at",
  "latitude",
  "longitude",
  "media_ids",
  "synced_at",
];

async function upsertRecords(connection, records) {
  const unique = [
    ...new Map(
      records
        .filter((record) => record?.source_key && record?.user_id)
        .map((record) => [`${record.source_key}`, record]),
    ).values(),
  ];
  const syncedAt = Date.now();
  for (let start = 0; start < unique.length; start += 50) {
    const chunk = unique.slice(start, start + 50);
    const valuesSql = chunk
      .map(() => `(${placeholders(recordColumns)})`)
      .join(", ");
    const args = chunk.flatMap((record) => recordArgs(record, syncedAt));
    await execute(
      connection,
      `INSERT INTO checkin_records (${recordColumns.join(", ")})
       VALUES ${valuesSql}
       ON DUPLICATE KEY UPDATE
       user_id = VALUES(user_id),
       record_date = VALUES(record_date),
       checkin_at = VALUES(checkin_at),
       checkin_type = VALUES(checkin_type),
       exception_type = VALUES(exception_type),
       group_name = VALUES(group_name),
       group_id = VALUES(group_id),
       schedule_id = VALUES(schedule_id),
       timeline_id = VALUES(timeline_id),
       location_title = VALUES(location_title),
       location_detail = VALUES(location_detail),
       wifi_name = VALUES(wifi_name),
       wifi_mac = VALUES(wifi_mac),
       notes = VALUES(notes),
       device_id = VALUES(device_id),
       schedule_checkin_at = VALUES(schedule_checkin_at),
       latitude = VALUES(latitude),
       longitude = VALUES(longitude),
       media_ids = VALUES(media_ids),
       synced_at = VALUES(synced_at)`,
      args,
    );
  }
  return unique.length;
}

async function upsertMonthlyReports(connection, payload) {
  const year = asInt(payload.year);
  const periodStart = asInt(payload.period_start_ms);
  const periodEndExclusive = asInt(payload.period_end_exclusive_ms);
  const periodStartDate = `${payload.period_start_date ?? ""}`.slice(0, 10);
  const syncedAt = Date.now();
  const unique = [
    ...new Map(
      (payload.reports ?? [])
        .filter((report) => report?.user_id && report?.report_json)
        .map((report) => [`${report.user_id}`, report]),
    ).values(),
  ];
  for (let start = 0; start < unique.length; start += 50) {
    const chunk = unique.slice(start, start + 50);
    const valuesSql = chunk.map(() => "(?, ?, ?, ?, ?, ?, ?)").join(", ");
    const args = chunk.flatMap((report) => {
      const userId = `${report.user_id}`;
      return [
        `${year}|${userId}|${periodStartDate}`,
        userId,
        year,
        periodStart,
        periodEndExclusive,
        typeof report.report_json === "string"
          ? report.report_json
          : JSON.stringify(report.report_json),
        syncedAt,
      ];
    });
    await execute(
      connection,
      `INSERT INTO monthly_report_snapshots
        (source_key, user_id, year, period_start, period_end_exclusive,
         report_json, synced_at)
       VALUES ${valuesSql}
       ON DUPLICATE KEY UPDATE
        user_id = VALUES(user_id),
        year = VALUES(year),
        period_start = VALUES(period_start),
        period_end_exclusive = VALUES(period_end_exclusive),
        report_json = VALUES(report_json),
        synced_at = VALUES(synced_at)`,
      args,
    );
  }
  return unique.length;
}

async function loadStats(connection) {
  const totals = (await execute(
    connection,
    `SELECT COUNT(*) AS record_count,
            COUNT(DISTINCT record_date) AS date_count
     FROM checkin_records`,
  )).rows?.[0] ?? {};
  const reportTotals = (await execute(
    connection,
    "SELECT COUNT(*) AS report_count FROM monthly_report_snapshots",
  )).rows?.[0] ?? {};
  const latest = (await execute(
    connection,
    "SELECT * FROM sync_runs ORDER BY started_at DESC LIMIT 1",
  )).rows?.[0] ?? null;
  return {
    checkin_record_count: asInt(totals.record_count),
    monthly_report_count: asInt(reportTotals.report_count),
    attendance_date_count: asInt(totals.date_count),
    last_run: latest,
  };
}

async function loadCheckinPage(connection, payload) {
  const userIds = uniqueStrings(payload.user_ids);
  const conditions = ["record_date >= ?", "record_date <= ?"];
  const args = [`${payload.start_date}`, `${payload.end_date}`];
  if (userIds.length) {
    conditions.push(`user_id IN (${placeholders(userIds)})`);
    args.push(...userIds);
  }
  const dataType = asInt(payload.data_type, 3);
  if (dataType === 1) {
    conditions.push("checkin_type NOT LIKE ?");
    args.push("%外出%");
  } else if (dataType === 2) {
    conditions.push("checkin_type LIKE ?");
    args.push("%外出%");
  }
  const where = conditions.join(" AND ");
  const totals = (await execute(
    connection,
    `SELECT COUNT(*) AS total_count,
            COUNT(DISTINCT user_id) AS user_count,
            SUM(CASE WHEN exception_type <> '' THEN 1 ELSE 0 END)
              AS exception_count
     FROM checkin_records WHERE ${where}`,
    args,
  )).rows?.[0] ?? {};
  const limit = Math.min(Math.max(asInt(payload.limit, 200), 1), 1000);
  const offset = Math.max(asInt(payload.offset), 0);
  const rows = (await execute(
    connection,
    `SELECT * FROM checkin_records WHERE ${where}
     ORDER BY checkin_at DESC LIMIT ? OFFSET ?`,
    [...args, limit, offset],
  )).rows ?? [];
  return {
    records: rows.map(rowRecord),
    total_count: asInt(totals.total_count),
    total_user_count: asInt(totals.user_count),
    total_exception_count: asInt(totals.exception_count),
  };
}

async function rawSummary(connection, payload, period) {
  const userIds = uniqueStrings(payload.user_ids);
  const periodExpression = period === "year"
    ? "SUBSTR(record_date, 1, 4)"
    : period === "month"
      ? "SUBSTR(record_date, 1, 7)"
      : "''";
  const actualWorkPunch = `checkin_type IN ('上班打卡', '下班打卡')
    AND exception_type NOT LIKE '%未打卡%'`;
  const args = [`${payload.start_date}`, `${payload.end_date}`, ...userIds];
  const rows = (await execute(
    connection,
    `WITH attendance_daily AS (
       SELECT user_id, record_date, ${periodExpression} AS period,
         MAX(group_name) AS group_name,
         SUM(CASE WHEN exception_type NOT LIKE '%未打卡%'
                  THEN 1 ELSE 0 END) AS record_count,
         SUM(CASE WHEN ${actualWorkPunch}
                  THEN 1 ELSE 0 END) AS actual_work_count,
         MAX(CASE WHEN ${actualWorkPunch}
                  THEN 1 ELSE 0 END) AS attended_day,
         MAX(CASE WHEN checkin_type IN ('上班打卡', '下班打卡')
                  THEN 1 ELSE 0 END) AS expected_day,
         MIN(CASE WHEN ${actualWorkPunch}
                  THEN checkin_at END) AS first_work_at,
         MAX(CASE WHEN ${actualWorkPunch}
                  THEN checkin_at END) AS last_work_at,
         MIN(CASE WHEN checkin_type IN ('上班打卡', '下班打卡')
                  THEN checkin_at END) AS first_expected_at,
         MAX(CASE WHEN checkin_type IN ('上班打卡', '下班打卡')
                  THEN checkin_at END) AS last_expected_at,
         SUM(CASE WHEN exception_type <> '' THEN 1 ELSE 0 END)
           AS exception_count,
         SUM(CASE WHEN exception_type LIKE '%时间异常%' THEN 1 ELSE 0 END)
           AS time_exception_count,
         SUM(CASE WHEN exception_type LIKE '%未打卡%' THEN 1 ELSE 0 END)
           AS not_checked_count,
         SUM(CASE WHEN LOWER(exception_type) LIKE '%wifi%' THEN 1 ELSE 0 END)
           AS wifi_exception_count,
         SUM(CASE WHEN exception_type LIKE '%地点异常%' THEN 1 ELSE 0 END)
           AS location_count,
         SUM(CASE WHEN exception_type LIKE '%非常用设备%' THEN 1 ELSE 0 END)
           AS device_count
       FROM checkin_records
       WHERE record_date >= ? AND record_date <= ?${userClause(userIds)}
       GROUP BY user_id, record_date
     )
     SELECT user_id, period, MAX(group_name) AS group_name,
       SUM(record_count) AS record_count,
       SUM(attended_day) AS attendance_days,
       SUM(expected_day) AS expected_days,
       SUM(CASE WHEN actual_work_count > 0 AND exception_count = 0
                THEN 1 ELSE 0 END) AS normal_attendance_days,
       SUM(COALESCE(last_work_at - first_work_at, 0)) AS work_ms,
       SUM(COALESCE(last_expected_at - first_expected_at, 0))
         AS standard_work_ms,
       SUM(exception_count) AS exception_count,
       SUM(CASE WHEN exception_count > 0 THEN 1 ELSE 0 END) AS exception_days,
       SUM(time_exception_count) AS time_exception_count,
       SUM(not_checked_count) AS not_checked_count,
       SUM(wifi_exception_count) AS wifi_exception_count,
       SUM(location_count) AS location_count,
       SUM(device_count) AS device_count
     FROM attendance_daily
     GROUP BY user_id, period
     ORDER BY period DESC, user_id`,
    args,
  )).rows ?? [];
  const includePeriod = period !== "all";
  return rows.map((row) => {
    const label = `${row.period ?? ""}`;
    const metrics = Object.fromEntries(
      [
        "checkinRecordCount",
        "attendanceDays",
        "normalAttendanceDays",
        "expectedDays",
        "restDays",
        "regularDays",
        "exceptionDays",
        "standardWorkHours",
        "regularWorkHours",
        "exceptionCount",
        "timeExceptionCount",
        "notCheckedInCount",
        "wifiExceptionCount",
        "lateCount",
        "lateMinutes",
        "earlyLeaveCount",
        "earlyLeaveMinutes",
        "absenceCount",
        "absenceMinutes",
        "missingCardCount",
        "locationExceptionCount",
        "deviceExceptionCount",
        "correctionCount",
        "approvalCheckinCount",
        "fieldCount",
        "outsideHours",
        "businessTripDays",
        "annualLeaveHours",
        "personalLeaveHours",
        "sickLeaveHours",
        "compensatoryLeaveHours",
        "marriageLeaveHours",
        "maternityLeaveDays",
        "paternityLeaveDays",
        "otherHours",
        "overtimeHours",
        "workdayOvertimeHours",
        "workdayOvertimeAsLeaveHours",
        "workdayOvertimeAsPayHours",
        "restdayOvertimeHours",
        "restdayOvertimeAsLeaveHours",
        "restdayOvertimeAsPayHours",
        "holidayOvertimeHours",
        "holidayOvertimeAsLeaveHours",
        "holidayOvertimeAsPayHours",
      ].map((key) => [key, 0]),
    );
    metrics.checkinRecordCount = asNumber(row.record_count);
    metrics.attendanceDays = asNumber(row.attendance_days);
    metrics.expectedDays = asNumber(row.expected_days);
    metrics.normalAttendanceDays = asNumber(row.normal_attendance_days);
    metrics.regularDays = asNumber(row.normal_attendance_days);
    metrics.exceptionDays = asNumber(row.exception_days);
    metrics.exceptionCount = asNumber(row.exception_count);
    metrics.regularWorkHours = asNumber(row.work_ms) / 3_600_000;
    metrics.standardWorkHours = asNumber(row.standard_work_ms) / 3_600_000;
    metrics.timeExceptionCount = asNumber(row.time_exception_count);
    metrics.notCheckedInCount = asNumber(row.not_checked_count);
    metrics.wifiExceptionCount = asNumber(row.wifi_exception_count);
    metrics.locationExceptionCount = asNumber(row.location_count);
    metrics.deviceExceptionCount = asNumber(row.device_count);
    return {
      year: includePeriod && label.length >= 4
        ? asInt(label.slice(0, 4), asInt(payload.start_date.slice(0, 4)))
        : asInt(payload.start_date.slice(0, 4)),
      month: includePeriod && label.length >= 7 ? asInt(label.slice(5, 7)) : null,
      period_label: includePeriod
        ? null
        : `${payload.start_date}~${payload.end_date}`,
      name: `${row.user_id ?? ""}`,
      user_id: `${row.user_id ?? ""}`,
      rule_names: row.group_name ? `${row.group_name}` : "--",
      departments: "--",
      source_record_count: 0,
      metrics,
    };
  });
}

async function loadDailySummary(connection, payload) {
  const userIds = uniqueStrings(payload.user_ids);
  const actualWorkPunch = `checkin_type IN ('上班打卡', '下班打卡')
    AND exception_type NOT LIKE '%未打卡%'`;
  const rows = (await execute(
    connection,
    `SELECT user_id,
       SUM(CASE WHEN exception_type NOT LIKE '%未打卡%'
                THEN 1 ELSE 0 END) AS record_count,
       COUNT(DISTINCT CASE WHEN ${actualWorkPunch}
                           THEN record_date END) AS attendance_days,
       SUM(CASE WHEN exception_type <> '' THEN 1 ELSE 0 END)
         AS exception_count,
       SUM(CASE WHEN exception_type <> '' THEN 1 ELSE 0 END) AS exception_days,
       SUM(CASE WHEN exception_type LIKE '%地点异常%' THEN 1 ELSE 0 END)
         AS location_exception_count,
       SUM(CASE WHEN exception_type LIKE '%非常用设备%' THEN 1 ELSE 0 END)
         AS device_exception_count
     FROM checkin_records
     WHERE record_date >= ? AND record_date <= ?${userClause(userIds)}
     GROUP BY user_id ORDER BY user_id`,
    [`${payload.start_date}`, `${payload.end_date}`, ...userIds],
  )).rows ?? [];
  return rows.map((row) => ({
    year: asInt(payload.start_date.slice(0, 4)),
    month: null,
    period_label: `${payload.start_date} 至 ${payload.end_date}`,
    name: `${row.user_id ?? ""}`,
    user_id: `${row.user_id ?? ""}`,
    rule_names: "--",
    departments: "--",
    source_record_count: 0,
    metrics: {
      checkinRecordCount: asNumber(row.record_count),
      attendanceDays: asNumber(row.attendance_days),
      exceptionCount: asNumber(row.exception_count),
      exceptionDays: asNumber(row.exception_days),
      locationExceptionCount: asNumber(row.location_exception_count),
      deviceExceptionCount: asNumber(row.device_exception_count),
    },
  }));
}

export async function handleDatabase(env, action, payload = {}) {
  const { connection, key } = databaseConnection(env);
  await ensureSchema(env, connection, key);

  if (action === "ping") {
    await execute(connection, "SELECT 1 AS ok");
    return { ok: true };
  }
  if (action === "load_stats") {
    return await loadStats(connection);
  }
  if (action === "load_checkin_page") {
    return await loadCheckinPage(connection, payload);
  }
  if (action === "save_checkins") {
    return { count: await upsertRecords(connection, payload.records ?? []) };
  }
  if (action === "replace_checkins") {
    const userIds = uniqueStrings(payload.user_ids);
    if (userIds.length) {
      await execute(
        connection,
        `DELETE FROM checkin_records
         WHERE record_date >= ? AND record_date < ?
           AND user_id IN (${placeholders(userIds)})`,
        [
          `${payload.period_start_date}`,
          `${payload.period_end_date}`,
          ...userIds,
        ],
      );
    }
    return { count: await upsertRecords(connection, payload.records ?? []) };
  }
  if (action === "save_monthly_reports") {
    return { count: await upsertMonthlyReports(connection, payload) };
  }
  if (action === "replace_monthly_reports") {
    const userIds = uniqueStrings(payload.user_ids);
    if (userIds.length) {
      await execute(
        connection,
        `DELETE FROM monthly_report_snapshots
         WHERE period_start >= ? AND period_start < ?
           AND user_id IN (${placeholders(userIds)})`,
        [
          asInt(payload.period_start_ms),
          asInt(payload.period_end_exclusive_ms),
          ...userIds,
        ],
      );
    }
    return { count: await upsertMonthlyReports(connection, payload) };
  }
  if (action === "load_synced_window_keys") {
    const userIds = uniqueStrings(payload.user_ids);
    const rows = (await execute(
      connection,
      `SELECT user_id, period_start FROM sync_windows
       WHERE period_start >= ? AND period_start < ?${userClause(userIds)}`,
      [
        asInt(payload.first_month_ms),
        asInt(payload.last_month_end_ms),
        ...userIds,
      ],
    )).rows ?? [];
    return rows.map((row) => `${row.period_start}|${row.user_id}`);
  }
  if (action === "load_report_snapshot_keys") {
    const userIds = uniqueStrings(payload.user_ids);
    const rows = (await execute(
      connection,
      `SELECT user_id, period_start, period_end_exclusive
       FROM monthly_report_snapshots
       WHERE period_start >= ? AND period_start < ?${userClause(userIds)}`,
      [
        asInt(payload.first_month_ms),
        asInt(payload.last_month_end_ms),
        ...userIds,
      ],
    )).rows ?? [];
    return rows.map(
      (row) =>
        `${row.period_start}|${row.period_end_exclusive}|${row.user_id}`,
    );
  }
  if (action === "load_monthly_report_snapshots") {
    const userIds = uniqueStrings(payload.user_ids);
    const rows = (await execute(
      connection,
      `SELECT user_id, year, period_start, period_end_exclusive, report_json
       FROM monthly_report_snapshots
       WHERE period_start >= ? AND period_start < ?${userClause(userIds)}
       ORDER BY period_start, user_id`,
      [
        asInt(payload.start_ms),
        asInt(payload.end_exclusive_ms),
        ...userIds,
      ],
    )).rows ?? [];
    return rows.map((row) => ({
      user_id: `${row.user_id ?? ""}`,
      year: asInt(row.year),
      period_start: asInt(row.period_start),
      period_end_exclusive: asInt(row.period_end_exclusive),
      report_json: typeof row.report_json === "string"
        ? row.report_json
        : JSON.stringify(row.report_json ?? {}),
    }));
  }
  if (action === "load_monthly_report") {
    const row = (await execute(
      connection,
      `SELECT report_json FROM monthly_report_snapshots
       WHERE user_id = ? AND period_start >= ? AND period_start < ?
       ORDER BY period_start DESC LIMIT 1`,
      [
        `${payload.user_id ?? ""}`,
        asInt(payload.period_start_ms),
        asInt(payload.period_end_exclusive_ms),
      ],
    )).rows?.[0];
    if (row == null) {
      return null;
    }
    return {
      report_json: typeof row.report_json === "string"
        ? row.report_json
        : JSON.stringify(row.report_json ?? {}),
    };
  }
  if (action === "mark_sync_windows") {
    const userIds = uniqueStrings(payload.user_ids);
    const start = asInt(payload.period_start_ms);
    const end = asInt(payload.period_end_exclusive_ms);
    const syncedAt = Date.now();
    for (const userId of userIds) {
      await execute(
        connection,
        `INSERT INTO sync_windows
          (source_key, user_id, period_start, period_end_exclusive, synced_at)
         VALUES (?, ?, ?, ?, ?)
         ON DUPLICATE KEY UPDATE
          period_end_exclusive = VALUES(period_end_exclusive),
          synced_at = VALUES(synced_at)`,
        [`${start}|${userId}`, userId, start, end, syncedAt],
      );
    }
    return { ok: true };
  }
  if (action === "start_sync_run") {
    const result = await execute(
      connection,
      `INSERT INTO sync_runs
        (started_at, first_month, last_month, user_count, sync_mode, status,
         record_count, report_count)
       VALUES (?, ?, ?, ?, ?, 'running', 0, 0)`,
      [
        Date.now(),
        `${payload.first_month}`,
        `${payload.last_month}`,
        asInt(payload.user_count),
        `${payload.mode ?? "full"}`,
      ],
    );
    return { id: asInt(result.lastInsertId) };
  }
  if (action === "finish_sync_run") {
    await execute(
      connection,
      `UPDATE sync_runs SET completed_at = ?, status = ?, record_count = ?,
        report_count = ?, error_message = ? WHERE id = ?`,
      [
        Date.now(),
        payload.succeeded ? "completed" : "failed",
        asInt(payload.record_count),
        asInt(payload.report_count),
        payload.error_message ?? null,
        asInt(payload.id),
      ],
    );
    return { ok: true };
  }
  if (action === "load_date_bounds") {
    const userIds = uniqueStrings(payload.user_ids);
    const row = (await execute(
      connection,
      `SELECT MIN(record_date) AS first_date, MAX(record_date) AS last_date
       FROM checkin_records WHERE 1 = 1${userClause(userIds)}`,
      userIds,
    )).rows?.[0];
    return row?.first_date && row?.last_date
      ? { first_date: dateKey(row.first_date), last_date: dateKey(row.last_date) }
      : null;
  }
  if (action === "load_latest_checkin_time") {
    const row = (await execute(
      connection,
      "SELECT MAX(checkin_at) AS latest_checkin_at FROM checkin_records",
    )).rows?.[0];
    return row?.latest_checkin_at == null
      ? null
      : { milliseconds: asInt(row.latest_checkin_at) };
  }
  if (action === "load_latest_monthly_report_time") {
    const row = (await execute(
      connection,
      "SELECT MAX(period_start) AS latest_report_at FROM monthly_report_snapshots",
    )).rows?.[0];
    return row?.latest_report_at == null
      ? null
      : { milliseconds: asInt(row.latest_report_at) };
  }
  if (action === "load_raw_year_summary") {
    return await rawSummary(connection, payload, "year");
  }
  if (action === "load_raw_month_summary") {
    return await rawSummary(connection, payload, "month");
  }
  if (action === "load_raw_all_summary") {
    return await rawSummary(connection, payload, "all");
  }
  if (action === "load_daily_summary") {
    return await loadDailySummary(connection, payload);
  }
  throw new ApiError(400, `不支持的数据库操作：${action}`);
}
