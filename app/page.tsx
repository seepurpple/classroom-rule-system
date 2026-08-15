"use client";

import { useMemo, useState } from "react";

const students = [
  { name: "김지우", role: "다독이", pay: 350, point: 2840, initials: "지", color: "lavender" },
  { name: "박서준", role: "반장", pay: 900, point: 3540, initials: "서", color: "orange" },
  { name: "이민서", role: "통장이", pay: 550, point: 1970, initials: "민", color: "blue" },
  { name: "최하윤", role: "칠판이", pay: 500, point: 1320, initials: "하", color: "pink" },
  { name: "정도윤", role: "지킴이", pay: 600, point: 910, initials: "도", color: "mint" },
];

const shopItems = [
  { name: "간식 (소)", price: 200, icon: "🍬", note: "텐텐 · 마이쮸 등", tone: "yellow" },
  { name: "간식 (중)", price: 600, icon: "🍪", note: "낱개 간식", tone: "peach" },
  { name: "자리 선정권", price: 1200, icon: "🪑", note: "최대 3명까지", tone: "purple" },
];

const transactions = [
  { date: "05. 16", title: "월급 지급", detail: "다독이 · 5월", amount: "+350", type: "earn" },
  { date: "05. 14", title: "교과 선생님 칭찬", detail: "영어 수업 참여", amount: "+200", type: "earn" },
  { date: "05. 10", title: "간식 (소)", detail: "마이쮸", amount: "-200", type: "spend" },
  { date: "05. 08", title: "선행 포인트", detail: "역할 자발적 대행", amount: "+60", type: "earn" },
];

export default function Home() {
  const [active, setActive] = useState("대시보드");
  const [notice, setNotice] = useState("");
  const [query, setQuery] = useState("");
  const [balance, setBalance] = useState(2840);

  const filteredStudents = useMemo(
    () => students.filter((student) => `${student.name} ${student.role}`.includes(query)),
    [query],
  );

  function showNotice(message: string) {
    setNotice(message);
    window.setTimeout(() => setNotice(""), 2600);
  }

  function buy(item: (typeof shopItems)[number]) {
    if (balance < item.price) {
      showNotice("포인트가 부족해요.");
      return;
    }
    setBalance((current) => current - item.price);
    showNotice(`${item.name} 구매 요청을 기록했어요.`);
  }

  return (
    <main className="app-shell">
      <aside className="sidebar">
        <div className="brand"><span>m</span><strong>모두의 역할</strong></div>
        <div className="class-switcher"><div><small>현재 학급</small><b>1학년 3반</b></div><span>⌄</span></div>
        <nav aria-label="주요 메뉴">
          {[
            ["▦", "대시보드"], ["♙", "학생·역할"], ["₩", "포인트 대장"], ["▱", "월급 관리"], ["◎", "학급 상점"],
          ].map(([icon, label]) => (
            <button key={label} className={active === label ? "nav-item active" : "nav-item"} onClick={() => { setActive(label); showNotice(`${label} 화면은 준비 중이에요.`); }}>
              <span>{icon}</span>{label}
            </button>
          ))}
        </nav>
        <div className="sidebar-foot">
          <button className="nav-item"><span>⚙</span>설정</button>
          <div className="teacher"><div className="avatar teacher-avatar">윤</div><div><b>윤선생님</b><small>담임 교사</small></div><span>⋮</span></div>
        </div>
      </aside>

      <section className="content">
        <header className="topbar">
          <div><p>2026년 5월 19일 · 월요일</p><h1>안녕하세요, 윤선생님 <span>👋</span></h1></div>
          <div className="top-actions"><button className="icon-button" aria-label="알림">♧<i /></button><button className="help-button">? <span>도움말</span></button></div>
        </header>

        <section className="hero-grid">
          <article className="hero-card">
            <div className="hero-copy"><span className="eyebrow">이번 달 포인트 현황</span><h2>작은 책임이<br /><em>큰 성장</em>이 되는 교실</h2><p>이번 달 역할 수행을 기록하고,<br />모두의 노력을 공정하게 보상하세요.</p><button onClick={() => showNotice("5월 월급 지급 초안을 만들었어요.")}>5월 월급 지급하기 <span>→</span></button></div>
            <div className="hero-art" aria-hidden="true"><div className="blob blob-one" /><div className="blob blob-two" /><div className="paper"><span>5월</span><b>급여일</b><strong>05. 21</strong><small>목요일</small></div><div className="coin coin-one">P</div><div className="coin coin-two">P</div><div className="spark">✦</div></div>
          </article>
          <article className="summary-card"><div className="summary-top"><span>다음 월급일</span><button onClick={() => showNotice("월급 기준일: 4주마다 해당 주 목요일")}>···</button></div><div className="calendar"><span>5월</span><div><b>21</b><small>목요일</small></div><strong>D-2</strong></div><div className="summary-bottom"><span>지급 예정 인원</span><b>28명 <i>›</i></b></div></article>
        </section>

        <section className="stat-grid" aria-label="학급 요약">
          <article className="stat-card"><div className="stat-icon lilac">♙</div><div><span>역할 배정률</span><strong>100<small>%</small></strong><p className="up">↗ 전체 학생 배정 완료</p></div></article>
          <article className="stat-card"><div className="stat-icon coral">P</div><div><span>이번 달 지급 포인트</span><strong>14,260<small>P</small></strong><p>지난 달보다 1,840P 많아요</p></div></article>
          <article className="stat-card"><div className="stat-icon yellow">⌁</div><div><span>대기 중인 요청</span><strong>3<small>건</small></strong><p className="alert">● 확인이 필요해요</p></div></article>
        </section>

        <section className="main-grid">
          <article className="panel role-panel"><div className="panel-heading"><div><h3>이번 달 역할 수행</h3><p>학생별 역할과 월급을 확인하세요.</p></div><button onClick={() => showNotice("전체 역할 목록을 열었어요.")}>전체 보기 <span>→</span></button></div><div className="student-list">
            {students.map((student, index) => <div className="student-row" key={student.name}><div className={`avatar ${student.color}`}>{student.initials}</div><div className="student-name"><b>{student.name}</b><span>{student.role}</span></div><div className="progress-wrap"><div className="progress"><i style={{ width: `${[91, 100, 76, 84, 69][index]}%` }} /></div><small>{["우수", "우수", "보통", "좋음", "보통"][index]}</small></div><strong>{student.pay.toLocaleString()}<small>P</small></strong><button className="more" aria-label={`${student.name} 상세`}>⋮</button></div>)}
          </div></article>
          <article className="panel activity-panel"><div className="panel-heading"><div><h3>최근 활동</h3><p>오늘도 기록이 쌓이고 있어요.</p></div><button onClick={() => showNotice("전체 활동 기록을 열었어요.")}>전체 보기 <span>→</span></button></div><div className="activity-list"><Activity badge="P" tone="purple" text="영어 선생님 칭찬" name="김지우" note="수업 참여 태도가 매우 좋아요." amount="+200P" time="14분 전" /><Activity badge="♙" tone="blue" text="역할 변경 요청" name="이민서" note="출석이 → 기록이" time="1시간 전" action="확인" /><Activity badge="⌁" tone="orange" text="상점 구매 요청" name="최하윤" note="간식 (중) · 600P" time="2시간 전" action="승인" /></div></article>
        </section>

        <section className="lower-grid">
          <article className="panel ledger-panel"><div className="panel-heading"><div><h3>김지우의 포인트 대장</h3><p>다독이 · 현재 보유 <b>{balance.toLocaleString()}P</b></p></div><button onClick={() => showNotice("포인트 지급·차감 양식을 열었어요.")}>+ 기록 추가</button></div><div className="ledger-table"><div className="ledger-head"><span>일자</span><span>내역</span><span>포인트</span></div>{transactions.map((row) => <div className="ledger-row" key={row.title}><span>{row.date}</span><div><b>{row.title}</b><small>{row.detail}</small></div><strong className={row.type}>{row.amount}P</strong></div>)}</div></article>
          <article className="panel shop-panel"><div className="panel-heading"><div><h3>학급 상점</h3><p>포인트로 보상을 선택해요.</p></div><button onClick={() => showNotice("학급 상점을 열었어요.")}>더 보기 <span>→</span></button></div><div className="shop-list">{shopItems.map((item) => <div className="shop-item" key={item.name}><div className={`item-icon ${item.tone}`}>{item.icon}</div><div><b>{item.name}</b><span>{item.note}</span></div><button onClick={() => buy(item)}>{item.price.toLocaleString()}P</button></div>)}</div></article>
        </section>
      </section>
      <aside className="right-rail"><div className="rail-title"><span>학생 찾기</span><button aria-label="닫기">×</button></div><label className="search"><span>⌕</span><input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="이름 또는 역할 검색" /></label><div className="search-results">{filteredStudents.map((student) => <button key={student.name} onClick={() => showNotice(`${student.name} 학생 정보를 열었어요.`)}><div className={`avatar ${student.color}`}>{student.initials}</div><span><b>{student.name}</b><small>{student.role}</small></span><em>{student.point.toLocaleString()}P</em></button>)}</div><div className="rule-note"><span>✦</span><div><b>운영 팁</b><p>역할 변경은 3주 수행 후<br />상호 동의로 가능해요.</p></div></div></aside>
      {notice && <div className="toast" role="status">✓ {notice}</div>}
    </main>
  );
}

function Activity({ badge, tone, text, name, note, amount, time, action }: { badge: string; tone: string; text: string; name: string; note: string; amount?: string; time: string; action?: string }) {
  return <div className="activity"><div className={`activity-badge ${tone}`}>{badge}</div><div><b>{text}</b><p><strong>{name}</strong> · {note}</p></div><aside>{amount && <em>{amount}</em>}{action && <button>{action}</button>}<small>{time}</small></aside></div>;
}
