-- 정상 흐름 점검: 넣어보고 조회한 뒤 전부 되돌린다.
--  현장 드롭다운 → 시나리오 A(대화·되묻기) → B(차단) → C(아차사고 경고) → D(TBM·알림) → 서명·인쇄 문서
START TRANSACTION;

-- ── 현장 2곳, 관리자 1명, 작성자 1명(두 현장), 승인자 1명(울산만)
INSERT INTO sites (name, mode, industry) VALUES ('울산 공장', 'VERIFY', '화학 플랜트');
SET @site = LAST_INSERT_ID();
INSERT INTO sites (name, mode, industry) VALUES ('여수 공장', 'VERIFY', '화학 플랜트');
SET @site2 = LAST_INSERT_ID();
INSERT INTO work_zones (site_id, code, name, is_confined) VALUES (@site, 'T-105', '저장탱크 105', TRUE);
SET @zone = LAST_INSERT_ID();
INSERT INTO users (email, password_hash, name, role, status, email_verified_at, email_verified_via) VALUES ('admin@check.local', 'x', '관리자', 'ADMIN', 'ACTIVE', NOW(6), 'ADMIN');
SET @admin = LAST_INSERT_ID();
-- 가입 → 인증 메일 → 링크 클릭 → 관리자 승인
INSERT INTO users (email, password_hash, name) VALUES ('writer@check.local', 'x', '작성자');
SET @writer = LAST_INSERT_ID();
INSERT INTO account_tokens (user_id, purpose, token_hash, expires_at) VALUES (@writer, 'EMAIL_VERIFY', SHA2('verify-link', 256), NOW(6) + INTERVAL 72 HOUR);
UPDATE account_tokens SET used_at = NOW(6) WHERE token_hash = SHA2('verify-link', 256) AND used_at IS NULL AND revoked_at IS NULL AND expires_at > NOW(6);
UPDATE users SET email_verified_at = NOW(6), email_verified_via = 'LINK' WHERE id = @writer;
UPDATE users SET status = 'ACTIVE' WHERE id = @writer;   -- 관리자 승인
INSERT INTO users (email, password_hash, name, role, status, email_verified_at, email_verified_via) VALUES ('approver@check.local', 'x', '승인자', 'MEMBER', 'ACTIVE', NOW(6), 'LINK');
SET @approver = LAST_INSERT_ID();
INSERT INTO site_members (user_id, site_id, role, granted_by) VALUES
 (@writer, @site, 'WRITER', @admin), (@writer, @site2, 'WRITER', @admin), (@approver, @site, 'APPROVER', @admin);

-- 대시보드 현장 드롭다운: ADMIN은 모든 현장, MEMBER는 권한 있는 현장
SELECT s.id, s.name FROM sites s
WHERE s.active AND (
      (SELECT role FROM users WHERE id = @writer) = 'ADMIN'
   OR EXISTS (SELECT 1 FROM site_members m WHERE m.site_id = s.id AND m.user_id = @writer AND m.status = 'ACTIVE'))
ORDER BY s.name;                                             -- 작성자: 울산·여수 2개
UPDATE users SET last_site_id = @site WHERE id = @writer;   -- 마지막 선택 현장 기억

-- 작업자 2명
INSERT INTO teams (name, team_type) VALUES ('정비팀', 'INTERNAL');
SET @team = LAST_INSERT_ID();
INSERT INTO workers (team_id, name, job_type) VALUES (@team, '김용접', '용접');
SET @w1 = LAST_INSERT_ID();
INSERT INTO workers (team_id, name, job_type) VALUES (@team, '이감시', '감시인');
SET @w2 = LAST_INSERT_ID();
INSERT INTO worker_sites (worker_id, site_id, assigned_from) VALUES (@w1, @site, CURDATE() - INTERVAL 60 DAY), (@w2, @site, CURDATE() - INTERVAL 60 DAY);
-- 김용접이 여수 공장으로도 지원 나감 → 두 현장 모두 배치 (울산 기록은 그대로)
INSERT INTO worker_sites (worker_id, site_id, assigned_from) VALUES (@w1, @site2, CURDATE());
INSERT INTO site_chemicals (site_id, zone_id, cas_no, name, max_quantity, unit) VALUES (@site, @zone, '108-88-3', '톨루엔', 2000, 'L');
INSERT INTO worker_qualifications (worker_id, qual_type, qual_code, qual_name, issued_on, expires_on, created_by)
VALUES (@w1, 'TRAINING', 'CONFINED_SPACE_SPECIAL', '밀폐공간 특별교육', CURDATE() - INTERVAL 30 DAY, NULL, @admin);

-- ── 시나리오 A: 대화 생성(제목 = 첫 질문) → 되묻기 → 답변
INSERT INTO agent_conversations (site_id, user_id, title) VALUES (@site, @writer, LEFT('오후에 T-105 탱크 내부 점검해. 서류 만들어줘.', 100));
SET @conv = LAST_INSERT_ID();
INSERT INTO agent_runs (site_id, user_id, conversation_id, task_type, mode, network_mode, status)
VALUES (@site, @writer, @conv, 'PERMIT_DRAFT', 'VERIFY', 'OPEN', 'WAITING_INPUT');
SET @run = LAST_INSERT_ID();
INSERT INTO agent_messages (conversation_id, seq, role, content, run_id) VALUES
 (@conv, 1, 'USER', '오후에 T-105 탱크 내부 점검해. 서류 만들어줘.', @run),
 (@conv, 2, 'ASSISTANT', '산소·유해가스 측정값을 알려주세요.', @run),
 (@conv, 3, 'USER', '산소 17.5%야.', @run);
UPDATE agent_conversations SET message_count = 3, last_message_at = NOW(6) WHERE id = @conv;

SELECT id, title, pinned, last_message_at FROM agent_conversations      -- 최근 항목
WHERE user_id = @writer AND deleted_at IS NULL ORDER BY pinned DESC, last_message_at DESC LIMIT 30;

INSERT INTO works (site_id, zone_id, team_id, work_date, title, work_type, is_high_risk, writer_id, agent_run_id)
VALUES (@site, @zone, @team, CURDATE(), '저장탱크 내부 점검', 'CONFINED', TRUE, @writer, @run);
SET @work = LAST_INSERT_ID();
INSERT INTO work_materials (work_id, cas_no, name) VALUES (@work, '108-88-3', '톨루엔(잔류)');
-- 이 구역에 있는 물질 (에이전트가 화기·밀폐 판단에 사용)
SELECT name, cas_no FROM site_chemicals WHERE site_id = @site AND (zone_id = @zone OR zone_id IS NULL) AND active;
INSERT INTO work_risk_factors (work_id, factor) VALUES (@work, 'CONFINED');
INSERT INTO work_workers (work_id, worker_id, site_id, role_in_work) VALUES (@work, @w1, @site, 'WORKER'), (@work, @w2, @site, 'ATTENDANT');

-- ── 시나리오 B: 산소 17.5% → 차단
INSERT INTO permits (site_id, work_id, permit_type, permit_no, valid_from, valid_to, writer_id, agent_run_id)
VALUES (@site, @work, 'CONFINED', 'CONF-CHECK-001', NOW(6), NOW(6) + INTERVAL 8 HOUR, @writer, @run);
SET @permit = LAST_INSERT_ID();
INSERT INTO permit_measurements (permit_id, measured_at, item, value, unit) VALUES (@permit, NOW(6), 'O2', 17.5, 'PCT');

SELECT r.rule_code, m.value, r.min_value, r.max_value,
       CASE WHEN m.value >= r.min_value AND m.value < r.max_value THEN 'PASS' ELSE r.severity END AS judged
FROM permit_measurements m
JOIN rules r ON r.target = CONCAT('measurement.', m.item) AND r.work_type = 'CONFINED' AND r.enabled
WHERE m.permit_id = @permit;

INSERT INTO rule_evaluations (site_id, target_type, target_id, result, input_snapshot, rules_applied, agent_run_id)
VALUES (@site, 'PERMIT', @permit, 'BLOCK', JSON_OBJECT('O2', 17.5), 1, @run);
SET @eval = LAST_INSERT_ID();
INSERT INTO rule_violations (evaluation_id, rule_id, actual_value, expected, severity, message, legal_basis)
SELECT @eval, id, '17.5', '18 이상 23.5 미만 %', severity, message, legal_basis FROM rules WHERE rule_code = 'CONFINED_O2_RANGE' AND version = 1;
UPDATE permits SET status = 'BLOCKED', last_evaluation_id = @eval WHERE id = @permit;
INSERT INTO record_history (site_id, target_type, target_id, action, actor_type, after_json)
VALUES (@site, 'PERMIT', @permit, 'BLOCK', 'SYSTEM', JSON_OBJECT('reason', 'CONFINED_O2_RANGE'));

SELECT p.permit_no, p.status, v.actual_value, v.expected, v.legal_basis   -- 감사 질의: 차단 이력과 근거
FROM permits p JOIN rule_violations v ON v.evaluation_id = p.last_evaluation_id WHERE p.site_id = @site;

-- ── 시나리오 B 이어서: 환기 후 재측정 → 통과 → 2단계 결재 → 작업 중 측정 → 연장
INSERT INTO permit_measurements (permit_id, phase, measured_at, item, value, unit, is_remeasure) VALUES (@permit, 'PRE_WORK', NOW(6), 'O2', 20.5, 'PCT', TRUE);
INSERT INTO rule_evaluations (site_id, target_type, target_id, result, input_snapshot, rules_applied) VALUES (@site, 'PERMIT', @permit, 'PASS', JSON_OBJECT('O2', 20.5), 1);
UPDATE permits SET last_evaluation_id = LAST_INSERT_ID(), status = 'PENDING' WHERE id = @permit;
-- 결재선: 이 현장 작업허가는 승인자 → 현장 관리자 2단계
INSERT INTO approval_policies (site_id, target_type, step_no, label, required_role, updated_by) VALUES
 (@site, 'PERMIT', 1, '부서 승인', 'APPROVER', @admin), (@site, 'PERMIT', 2, '안전 최종 승인', 'SITE_ADMIN', @admin);
INSERT INTO approvals (site_id, target_type, target_id, requested_by) VALUES (@site, 'PERMIT', @permit, @writer);
SET @appr = LAST_INSERT_ID();
INSERT INTO approval_steps (approval_id, step_no, label, required_role, status)
SELECT @appr, step_no, label, required_role, IF(step_no = 1, 'PENDING', 'WAITING') FROM approval_policies WHERE site_id = @site AND target_type = 'PERMIT';
UPDATE approval_steps SET status = 'APPROVED', decided_by = @approver, decided_at = NOW(6) WHERE approval_id = @appr AND step_no = 1;
UPDATE approval_steps SET status = 'PENDING' WHERE approval_id = @appr AND step_no = 2;
UPDATE approvals SET current_step = 2 WHERE id = @appr;
UPDATE approval_steps SET status = 'APPROVED', decided_by = @admin, decided_at = NOW(6) WHERE approval_id = @appr AND step_no = 2;
UPDATE approvals SET status = 'APPROVED', approver_id = @admin, decided_at = NOW(6) WHERE id = @appr;
UPDATE permits SET status = 'APPROVED' WHERE id = @permit;
SELECT step_no, label, status FROM approval_steps WHERE approval_id = @appr ORDER BY step_no;
-- 작업 중 2시간마다 측정 (승인 후에도 DURING은 넣을 수 있음)
INSERT INTO permit_measurements (permit_id, phase, measured_at, item, value, unit) VALUES (@permit, 'DURING', NOW(6), 'O2', 20.3, 'PCT');
-- 작업이 길어져 2시간 연장 요청 → 승인
INSERT INTO permit_events (permit_id, site_id, event_type, reason, new_valid_to, requested_by)
SELECT id, site_id, 'EXTEND', '배관 내부 잔류물 추가 제거', valid_to + INTERVAL 2 HOUR, @writer FROM permits WHERE id = @permit;
UPDATE permit_events SET status = 'APPROVED', decided_by = @approver, decided_at = NOW(6) WHERE id = LAST_INSERT_ID();
SELECT p.permit_no, p.valid_to AS original_end,
       COALESCE((SELECT MAX(e.new_valid_to) FROM permit_events e WHERE e.permit_id = p.id AND e.event_type = 'EXTEND' AND e.status = 'APPROVED'), p.valid_to) AS effective_end
FROM permits p WHERE p.id = @permit;

-- ── 시나리오 C: 아차사고 → 같은 구역 작업에 경고 → 작성자 확인
INSERT INTO near_misses (site_id, zone_id, occurred_at, title, description, reporter_id)
VALUES (@site, @zone, NOW(6) - INTERVAL 3 DAY, '탱크 맨홀 근처 미끄러짐', '맨홀 주변 기름 유출로 미끄러질 뻔함', @writer);
SET @nm = LAST_INSERT_ID();
INSERT INTO work_warnings (site_id, work_id, source_type, near_miss_id, message)
VALUES (@site, @work, 'NEAR_MISS', @nm, '3일 전 같은 구역에서 미끄러짐 아차사고가 있었습니다.');
SET @warn = LAST_INSERT_ID();
UPDATE work_warnings SET acknowledged_by = @writer, acknowledged_at = NOW(6), ack_note = '맨홀 주변 흡착포 설치' WHERE id = @warn;
INSERT INTO corrective_actions (site_id, source_type, source_id, title, assignee_id, due_date, created_by)
VALUES (@site, 'NEAR_MISS', @nm, '맨홀 주변 유출 방지턱 설치', @writer, CURDATE() + INTERVAL 7 DAY, @approver);

-- ── 시나리오 D: TBM 참석·서명 → 차단 알림 (작성자·승인자)
INSERT INTO tbm_records (site_id, team_id, zone_id, tbm_date, held_at, attendee_count, status, writer_id)
VALUES (@site, @team, @zone, CURDATE(), NOW(6), 2, 'DONE', @writer);
SET @tbm = LAST_INSERT_ID();
INSERT INTO tbm_works (tbm_id, work_id, site_id, tbm_date) VALUES (@tbm, @work, @site, CURDATE());   -- 이 TBM이 다룬 작업
INSERT INTO tbm_attendees (tbm_id, worker_id, site_id, health_ok) VALUES (@tbm, @w1, @site, TRUE), (@tbm, @w2, @site, TRUE);
INSERT INTO signatures (site_id, signer_type, worker_id, target_type, target_id, purpose, content_sha256)
VALUES (@site, 'WORKER', @w1, 'TBM', @tbm, 'ATTENDEE', SHA2('tbm-content-v1', 256));

INSERT INTO notifications (site_id, type, severity, title, message, target_type, target_id, actor_type, dedupe_key)
VALUES (@site, 'BLOCKED', 'CRITICAL', '작업허가 차단', '산소농도 17.5%로 기준 미달입니다. 환기 후 재측정하세요.', 'PERMIT', @permit, 'SYSTEM', CONCAT('BLOCKED:', @eval));
SET @noti = LAST_INSERT_ID();
-- 받는 사람: 작성자 + 이 현장 승인자 (site_members에서 찾음)
INSERT INTO notification_recipients (notification_id, user_id)
SELECT @noti, @writer UNION
SELECT @noti, m.user_id FROM site_members m WHERE m.site_id = @site AND m.role = 'APPROVER' AND m.status = 'ACTIVE';
SELECT COUNT(*) AS badge FROM notification_recipients WHERE user_id = @writer AND read_at IS NULL AND dismissed_at IS NULL;
UPDATE notification_recipients SET read_at = NOW(6), dismissed_at = NOW(6) WHERE notification_id = @noti AND user_id = @writer;  -- X 버튼
SELECT u.name, r.dismissed_at IS NOT NULL AS removed FROM notification_recipients r JOIN users u ON u.id = r.user_id WHERE r.notification_id = @noti;

-- ── 위험성평가: AI 초안 → 화면에서 수정(임시저장) → 저장 → 제출 → PDF 출력(비동기)
INSERT INTO risk_assessments (site_id, work_id, assess_date, writer_id, agent_run_id, form_data)
VALUES (@site, @work, CURDATE(), @writer, @run, JSON_OBJECT('note', 'AI 초안'));
SET @risk = LAST_INSERT_ID();
INSERT INTO risk_assessment_items (assessment_id, seq, work_step, hazard, accident_type, frequency, severity, risk_level, controls)
VALUES (@risk, 1, '탱크 진입', '산소결핍에 의한 질식', 'ASPHYXIATION', 4, 4, 'HIGH', '환기, 측정');
INSERT INTO record_history (site_id, target_type, target_id, action, actor_type, actor_id) VALUES (@site, 'RISK', @risk, 'AI_DRAFT', 'AGENT', @run);

-- 화면 열기: 현재 판(lock_version)을 기준으로 임시저장 시작
SELECT lock_version INTO @base FROM risk_assessments WHERE id = @risk;
INSERT INTO form_drafts (site_id, user_id, target_type, target_id, base_version, schema_version, title, draft_json)
VALUES (@site, @writer, 'RISK', @risk, @base, 'v1', '저장탱크 내부 점검 위험성평가', JSON_OBJECT('controls', '환기, 측정'));
SET @draft = LAST_INSERT_ID();
-- 자동 임시저장 2번 (순번 증가). 늦게 도착한 옛 요청(seq 1)은 아무것도 바꾸지 못함
UPDATE form_drafts SET draft_json = JSON_OBJECT('controls', '환기, 측정, 감시인'), client_seq = 1 WHERE id = @draft AND client_seq < 1;
UPDATE form_drafts SET draft_json = JSON_OBJECT('controls', '환기, 측정, 감시인 배치, 송기마스크'), client_seq = 2 WHERE id = @draft AND client_seq < 2;
UPDATE form_drafts SET draft_json = JSON_OBJECT('controls', '옛 내용'), client_seq = 1 WHERE id = @draft AND client_seq < 1;
SELECT client_seq, JSON_UNQUOTE(draft_json->'$.controls') AS saved FROM form_drafts WHERE id = @draft;   -- 2, 송기마스크 포함

-- [저장]: 기준 판이 그대로일 때만 반영 (다른 사람이 먼저 고쳤으면 0행 → 충돌 안내)
UPDATE risk_assessment_items SET controls = '환기, 측정, 감시인 배치, 송기마스크' WHERE assessment_id = @risk AND seq = 1;
UPDATE risk_assessments SET form_data = JSON_OBJECT('note', '사람 수정'), lock_version = lock_version + 1
WHERE id = @risk AND lock_version = @base;
SELECT ROW_COUNT() AS saved_rows;                                                                        -- 1
INSERT INTO record_history (site_id, target_type, target_id, action, actor_type, actor_id) VALUES (@site, 'RISK', @risk, 'UPDATE', 'USER', @writer);
DELETE FROM form_drafts WHERE id = @draft;

-- [제출] → 이후 내용 잠김
UPDATE risk_assessments SET status = 'PENDING' WHERE id = @risk;
SELECT work_step, risk_score FROM risk_assessment_items WHERE assessment_id = @risk;                     -- 16

-- [PDF 출력] 두 번 눌러도 작업 1개 (idempotency_key)
SELECT lock_version INTO @ver FROM risk_assessments WHERE id = @risk;
INSERT INTO async_jobs (site_id, requested_by, job_type, target_type, target_id, target_version, params, idempotency_key)
VALUES (@site, @writer, 'EXPORT_PDF', 'RISK', @risk, @ver, JSON_OBJECT('formType', 'RISK_ASSESSMENT'), CONCAT('EXPORT_PDF:RISK:', @risk, ':v', @ver))
ON DUPLICATE KEY UPDATE id = LAST_INSERT_ID(id);
SET @job = LAST_INSERT_ID();
INSERT INTO async_jobs (site_id, requested_by, job_type, target_type, target_id, target_version, idempotency_key)
VALUES (@site, @writer, 'EXPORT_PDF', 'RISK', @risk, @ver, CONCAT('EXPORT_PDF:RISK:', @risk, ':v', @ver))
ON DUPLICATE KEY UPDATE id = LAST_INSERT_ID(id);
SELECT LAST_INSERT_ID() = @job AS same_job;                                                              -- 1

-- 작업자: 하나 가져가기 → 처리 → 문서 기록 → 완료
SELECT id FROM async_jobs WHERE status = 'QUEUED' AND run_after <= NOW(6) ORDER BY id LIMIT 1 FOR UPDATE SKIP LOCKED;
UPDATE async_jobs SET status = 'RUNNING', locked_by = 'spring-1', started_at = NOW(6), attempts = attempts + 1 WHERE id = @job;
INSERT INTO form_templates (form_type, version, json_schema, print_template_path, status, created_by)
VALUES ('RISK_ASSESSMENT', 'v1', JSON_OBJECT('type', 'object'), 'templates/risk_assessment_v1.html', 'ACTIVE', @admin);
INSERT INTO generated_documents (site_id, form_type, template_id, target_type, target_id, source_version, seq, file_path, file_sha256, page_count, data_snapshot, created_by_type, created_by_id)
VALUES (@site, 'RISK_ASSESSMENT', LAST_INSERT_ID(), 'RISK', @risk, @ver, 1, CONCAT('docs/risk/', @risk, '-1.pdf'), SHA2('pdf-bytes', 256), 2, JSON_OBJECT('risk_id', @risk), 'USER', @writer);
SET @doc = LAST_INSERT_ID();
UPDATE async_jobs SET status = 'DONE', progress = 100, result_document_id = @doc, finished_at = NOW(6) WHERE id = @job;
INSERT INTO notifications (site_id, type, title, message, target_type, target_id, actor_type)
VALUES (@site, 'DOCUMENT_READY', 'PDF 준비 완료', '위험성평가서 PDF가 준비되었습니다.', 'DOCUMENT', @doc, 'SYSTEM');
INSERT INTO notification_recipients (notification_id, user_id) VALUES (LAST_INSERT_ID(), @writer);
INSERT INTO record_access_logs (user_id, site_id, resource_type, resource_id, action) VALUES (@approver, @site, 'DOCUMENT', @doc, 'DOWNLOAD');
INSERT INTO agent_feedback (run_id, user_id, rating, reason_code) VALUES (@run, @writer, 'DOWN', 'MISSING_HAZARD');

ROLLBACK;
SELECT '정상 흐름 점검 완료 (데이터는 되돌림)' AS result;
