import assert from "node:assert/strict";
import { access, readFile } from "node:fs/promises";
import test from "node:test";

const templateRoot = new URL("../", import.meta.url);

async function render() {
  const workerUrl = new URL("../dist/server/index.js", import.meta.url);
  workerUrl.searchParams.set("test", `${process.pid}-${Date.now()}`);
  const { default: worker } = await import(workerUrl.href);

  return worker.fetch(
    new Request("http://localhost/", {
      headers: { accept: "text/html" },
    }),
    {
      ASSETS: {
        fetch: async () => new Response("Not found", { status: 404 }),
      },
    },
    {
      waitUntil() {},
      passThroughOnException() {},
    },
  );
}

test("server-renders Supabase classroom app shell", async () => {
  const response = await render();
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);

  const html = await response.text();
  assert.match(html, /<title>모두의 역할 \| 1학년 3반<\/title>/i);
  assert.match(html, /Supabase 학급 데이터를 불러오는 중/);
  assert.match(html, /og\.png/);
});

test("keeps student identities anonymous and Supabase flows present", async () => {
  const [page, layout, packageJson] = await Promise.all([
    readFile(new URL("../app/page.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/layout.tsx", import.meta.url), "utf8"),
    readFile(new URL("../package.json", import.meta.url), "utf8"),
  ]);

  assert.match(page, /"use client"/);
  assert.match(page, /function Apply/);
  assert.match(page, /function Manage/);
  assert.match(page, /25명/);
  assert.doesNotMatch(page, /김지우|박서준|이민서/);
  assert.match(layout, /generateMetadata/);
  assert.doesNotMatch(packageJson, /react-loading-skeleton/);
  assert.match(page, /submit_role_applications/);
  assert.match(page, /teacher_lottery/);
  assert.match(page, /teacher_reset/);
  assert.match(page, /teacher_change_password/);
  assert.match(page, /teacher_record_class_points/);
  assert.match(page, /teacher_record_reading_bonus/);
  assert.match(page, /PAYROLL_RULES/);
  assert.match(page, /teacher_run_payroll/);
  assert.match(page, /teacher_update_role_salary/);
  assert.match(page, /PublicLedger/);
  assert.match(page, /publicLedger/);
  assert.match(page, /ledger-pagination/);
  assert.match(page, /PayrollAdjustments/);
  assert.match(page, /모두의 역할/);
  assert.match(page, /CSV 내려받기/);
  assert.doesNotMatch(page, /localhost:3001/);

  await assert.rejects(
    access(new URL("app/_sites-preview/SkeletonPreview.tsx", templateRoot)),
  );
});
