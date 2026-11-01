import type { CockpitRecommendationPace } from "../lib/cockpitRecommendationPace";
import type { Language } from "../types";
import "./RecommendationPace.css";

interface Props {
  pace: CockpitRecommendationPace | null;
  language: Language;
  compact?: boolean;
}

function number(value: number, language: Language): string {
  return value.toLocaleString(language === "en" ? "en-US" : "zh-CN", { maximumFractionDigits: 2 });
}

function compactDelta(pace: CockpitRecommendationPace): string {
  // Partial observations give a lower bound: ≥4.6 may become ≥4, never ≥5.
  const value = pace.isLowerBound ? Math.floor(pace.deltaPercent)
    : Math.sign(pace.deltaPercent) * Math.round(Math.abs(pace.deltaPercent));
  return `${pace.isLowerBound ? "≥" : ""}${value > 0 ? "+" : value < 0 ? "-" : ""}${Math.abs(value)}%`;
}

function comparison(pace: CockpitRecommendationPace | null, language: Language): string {
  const zh = language !== "en";
  if (!pace) return zh ? "今日推荐节奏暂不可用" : "Today's recommendation pace is unavailable";
  if (pace.isLowerBound) {
    if (pace.deltaPercent <= 0) return zh ? "今日节奏需要完整的用量数据" : "Today's pace needs complete usage data";
    const lowerBound = number(Math.floor(pace.deltaPercent * 100) / 100, language);
    return zh ? `今日：至少快 ${lowerBound} 个周额度百分点 · 数据不完整`
      : `Today: at least ${lowerBound} pp ahead · incomplete data`;
  }
  if (Math.abs(pace.deltaPercent) < 0.005) return zh ? "今日：符合推荐节奏" : "Today: on recommendation pace";
  const delta = number(Math.abs(pace.deltaPercent), language);
  return zh ? `今日：比推荐节奏${pace.deltaPercent > 0 ? "快" : "慢"} ${delta} 个周额度百分点`
    : `Today: ${delta} pp ${pace.deltaPercent > 0 ? "ahead of" : "behind"} recommendation`;
}

function explanation(pace: CockpitRecommendationPace | null, language: Language): string {
  const zh = language !== "en";
  if (!pace) return zh ? "需要同一账户的新鲜周额度与今日用量观测；暂无数据不会当作 0。"
    : "Fresh weekly quota and today's observations from the same account are required; unavailable is not zero.";
  const used = number(pace.observedUsedPercent, language);
  const expected = number(pace.expectedUsedPercent, language);
  const suggested = number(pace.suggestedPercent, language);
  const partial = pace.isLowerBound ? (zh ? "观测不完整，偏差仅为下界，不能据此确定有结余。" : "Observations are incomplete: the deviation is a lower bound and cannot establish a reserve.") : "";
  return zh ? `今日已观测 ${used}%，当前参考 ${expected}%（全天建议 ${suggested}% × 本地日进度）。单位均为周额度百分点；个人上限独立，全天建议不因时间变晚而缩小。${partial}`
    : `Observed today ${used}%; expected by now ${expected}% (full-day recommendation ${suggested}% × elapsed local-day fraction). All values use weekly quota percentage points; personal caps remain separate and the full-day target does not shrink as the day passes. ${partial}`.trim();
}

/** A daily-plan comparison, independent of the account's exhaustion forecast and weekly progress bar. */
export function RecommendationPace({ pace, language, compact = false }: Props) {
  const label = comparison(pace, language);
  const detail = explanation(pace, language);
  const accessible = `${label}. ${detail}`;
  const value = pace ? compactDelta(pace) : "—";
  if (compact) return <span className="recommendation-pace-compact" title={accessible} aria-label={accessible}>
    {language === "en" ? "Pace" : "节奏"} {value}
  </span>;
  return <div className="recommendation-pace" aria-label={language === "en" ? "Daily recommendation pace" : "每日推荐节奏"}>
    <strong>{label}</strong><small>{detail}</small>
  </div>;
}
