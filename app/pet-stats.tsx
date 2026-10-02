"use client";

import { useState } from "react";
import { getSpecies } from "@/lib/catalog";
import { emptyStats, earnedStatPoints, STAT_KEYS, STAT_LABELS, petStats, statLimit, statTotal, validAllocation } from "@/lib/stats";
import type { Pet, Stats } from "@/lib/types";

export function PetStatsEditor({ pet, busy, save }: { pet: Pet; busy: boolean; save: (allocation: Stats) => Promise<unknown> }) {
  const [draft, setDraft] = useState<Stats>(() => ({ ...(pet.statAllocation ?? emptyStats()) }));
  const base = getSpecies(pet.speciesId)!.baseStats;
  const earned = earnedStatPoints(pet.level), limit = statLimit(pet.level), remaining = earned - statTotal(draft);
  const valid = validAllocation(draft, pet.level);
  const totals = petStats({ ...pet, statAllocation: draft });
  const changed = STAT_KEYS.some(key => draft[key] !== (pet.statAllocation?.[key] ?? 0));
  return <form className="pc-stats" onSubmit={async event => {
    event.preventDefault();
    if (valid && changed && !busy) await save(draft);
  }}>
    <div className="pc-stats-summary" aria-live="polite"><strong>남은 포인트 {remaining}</strong><span>총 획득 {earned} · 스탯별 최대 +{limit}</span></div>
    <p className="pc-subtle">레벨업마다 +3, Lv.10 첫 진화 시 +7. 한 스탯에는 총 획득 포인트의 40%까지 투자해요. 소수점은 버려요.</p>
    <div className="pc-stat-list">{STAT_KEYS.map(key => <div className="pc-stat-row" key={key}>
      <div><label htmlFor={`stat-${pet.id}-${key}`}>{STAT_LABELS[key]}</label><small>기본 {base[key]} + 투자 {draft[key]}</small></div>
      <strong aria-label={`${STAT_LABELS[key]} 합계`}>{totals[key]}</strong>
      <div className="pc-stat-controls">
        <button type="button" aria-label={`${STAT_LABELS[key]} 1 감소`} disabled={busy || draft[key] <= 0} onClick={() => setDraft({ ...draft, [key]: draft[key] - 1 })}>−</button>
        <input id={`stat-${pet.id}-${key}`} aria-label={`${STAT_LABELS[key]} 투자 포인트`} type="number" inputMode="numeric" min={0} max={limit} step={1} value={draft[key]} disabled={busy} onChange={event => setDraft({ ...draft, [key]: Number(event.target.value) })}/>
        <button type="button" aria-label={`${STAT_LABELS[key]} 1 증가`} disabled={busy || remaining <= 0 || draft[key] >= limit} onClick={() => setDraft({ ...draft, [key]: draft[key] + 1 })}>+</button>
      </div>
    </div>)}</div>
    <p className="pc-subtle">배분은 무료로 다시 바꿀 수 있어요. 저장을 눌러야 반영돼요.</p>
    {!valid && <p role="alert" className="pc-warn">스탯별 한도와 남은 포인트를 확인해 주세요. 0 이상의 정수만 입력해요.</p>}
    <div className="pc-stats-actions"><button type="button" className="pc-text" disabled={busy || statTotal(draft) === 0} onClick={() => setDraft(emptyStats())}>배분 초기화</button><button className="pc-primary" disabled={busy || !valid || !changed}>{busy ? "저장 중…" : "스탯 배분 저장"}</button></div>
  </form>;
}
