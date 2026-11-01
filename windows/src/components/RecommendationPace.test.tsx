// @vitest-environment jsdom
import "@testing-library/jest-dom/vitest";
import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, expect, it } from "vitest";
import type { CockpitRecommendationPace } from "../lib/cockpitRecommendationPace";
import { RecommendationPace } from "./RecommendationPace";

afterEach(cleanup);
const pace: CockpitRecommendationPace = {
  suggestedPercent: 20, observedUsedPercent: 15.6, expectedUsedPercent: 10,
  deltaPercent: 5.6, elapsedDayFraction: .5, isLowerBound: false,
};

it("uses compact whole-point comparison with the exact weekly-point basis accessible", () => {
  render(<RecommendationPace pace={pace} language="en" compact />);
  const reading = screen.getByText("Pace +6%");
  expect(reading).toHaveAccessibleName(/Today: 5.6 pp ahead of recommendation/);
  expect(reading).toHaveAttribute("title", expect.stringContaining("Observed today 15.6%; expected by now 10%"));
  expect(reading).toHaveAttribute("title", expect.stringContaining("full-day recommendation 20%"));
  expect(reading).toHaveAttribute("title", expect.stringContaining("weekly quota percentage points"));
});

it("rounds negative exact half points away from zero like the Mac and native clients", () => {
  render(<RecommendationPace pace={{ ...pace, observedUsedPercent: 4.5, deltaPercent: -5.5 }} language="en" compact />);
  expect(screen.getByText("Pace -6%")).toHaveAccessibleName(/Today: 5.5 pp behind recommendation/);
});

it("rounds partial bounds outward and never labels negative bounds as reserve", () => {
  const { rerender } = render(<RecommendationPace pace={{ ...pace, isLowerBound: true }} language="en" compact />);
  expect(screen.getByText("Pace ≥+5%")).toHaveAccessibleName(/at least 5.6 pp ahead · incomplete data/);
  rerender(<RecommendationPace pace={{ ...pace, deltaPercent: -5.6, observedUsedPercent: 4.4, isLowerBound: true }} language="en" compact />);
  expect(screen.getByText("Pace ≥-6%")).toHaveAccessibleName(/Today's pace needs complete usage data/);
  expect(screen.getByText("Pace ≥-6%")).toHaveAttribute("title", expect.stringContaining("cannot establish a reserve"));
  rerender(<RecommendationPace pace={{ ...pace, deltaPercent: 0, isLowerBound: true }} language="en" />);
  expect(screen.getByText("Today's pace needs complete usage data")).toBeInTheDocument();
  expect(screen.queryByText("Today: on recommendation pace")).not.toBeInTheDocument();
});

it("explains the local-day reference in Chinese and keeps it separate from quota forecasts", () => {
  const { container } = render(<RecommendationPace pace={pace} language="zh-CN" />);
  expect(screen.getByLabelText("每日推荐节奏")).toHaveTextContent("今日：比推荐节奏快 5.6 个周额度百分点");
  expect(container).toHaveTextContent("全天建议 20% × 本地日进度");
  expect(container).toHaveTextContent("个人上限独立");
  expect(container).toHaveTextContent("全天建议不因时间变晚而缩小");
  expect(container.textContent).not.toContain("预计用尽");
  expect(container.querySelector('[role="progressbar"]')).not.toBeInTheDocument();
});

it("distinguishes missing data from a measured on-pace zero", () => {
  const { rerender } = render(<RecommendationPace pace={null} language="en" compact />);
  expect(screen.getByText("Pace —")).toHaveAccessibleName(/unavailable is not zero/);
  rerender(<RecommendationPace pace={{ ...pace, deltaPercent: 0, observedUsedPercent: 10 }} language="en" compact />);
  expect(screen.getByText("Pace 0%")).toHaveAccessibleName(/Today: on recommendation pace/);
  rerender(<RecommendationPace pace={{ ...pace, deltaPercent: -5, observedUsedPercent: 5 }} language="en" />);
  expect(screen.getByText("Today: 5 pp behind recommendation")).toBeInTheDocument();
});
