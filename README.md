markdown
# Maven Fuzzy Factory: Landing Page A/B Test Analysis

## 📋 Table of Contents

- [Project Overview](#-project-overview)
- [Business Context & Problem Statement](#-business-context--problem-statement)
- [Data & Methodology](#%EF%B8%8F-data--methodology)
- [Analysis Process & Thinking](#-analysis-process--thinking)
- [Key Findings & Business Recommendations](#-key-findings--business-recommendations)
- [Broader Implications & Next Steps](#-broader-implications--next-steps)
- [References](#-references)

---

## 🎯 Project Overview

**Maven Fuzzy Factory**, an online children's toy retailer, was experiencing an **unusually high bounce rate** of **60%** on their **homepage**. The website manager hypothesized that a new landing page design could better engage visitors and reduce this bounce rate.

This project analyzes the results of an **A/B test** comparing the existing **homepage (`/home`)** against a **new landing page (`/lander-1`)** for a specific traffic segment. Using **SQL** for data extraction, transformation, and analysis, I determined whether the new page drove a **statistically significant improvement** in bounce rates.

**Objective:** Determine if the new landing page (`/lander-1`) reduces bounce rates compared to the original homepage (`/home`).

**Key Skills Demonstrated:**
- Advanced SQL (CTEs, Window Functions, Joins)
- A/B Testing Methodology
- Statistical Analysis (Confidence Intervals)
- Data-Driven Business Decision Making

**Tech Stack:** MySQL, SQL

---

## 📊 Business Context & Problem Statement

### The Situation

The Maven Fuzzy Factory website had a **60% bounce rate** on its homepage. For every 10 visitors arriving at the site, 6 left immediately without exploring any other pages. This represents:

- **Lost Revenue:** Visitors who bounce cannot make purchases
- **Wasted Marketing Spend:** Ad dollars spent bringing traffic to a page that fails to engage
- **Missed Opportunities:** No chance to showcase products or build brand awareness

### The Hypothesis

A new landing page (`/lander-1`) was designed with a cleaner layout, clearer value proposition, and more prominent call-to-action buttons. The hypothesis was that this improved user experience would encourage visitors to explore further, reducing the bounce rate.

### The Test Design

The A/B test was conducted on a specific traffic segment:

- **Traffic Source:** Google Search (`utm_source = 'gsearch'`)
- **Campaign Type:** Non-brand keywords (`utm_campaign = 'nonbrand'`)
- **Test Groups:**
  - **Control Group:** Visitors saw the original homepage (`/home`)
  - **Test Group:** Visitors saw the new landing page (`/lander-1`)

### The Business Question

> **"Can we be 95% confident that the new landing page has a lower bounce rate than the original homepage?"**

---

## 🗃️ Data & Methodology

### Dataset

The dataset for this project is part of the Maven Analytics guided project: **Landing Page Test**. You can access the dataset and the full project brief here:

🔗 [Maven Analytics: Landing Page Test](https://app.mavenanalytics.io/guided-projects/8c4fe9d3-e71c-4333-82a6-0c06ff1557a1)

> **Note:** The dataset is available through a Maven Analytics subscription. The link above provides access to the guided project and its associated data files.

### Data Sources

Two primary tables from the e-commerce database were used:

| Table | Purpose | Key Fields |
|--------|-------------|---------------|
| `website_sessions` | Session-level data containing visitor information, traffic source, and session metadata | `website_session_id`, `created_at`, `user_id`, `is_repeat_session`, `utm_source`, `utm_campaign`, `utm_content`, `device_type`, `http_referer` |
| `website_pageviews` | Page-level data showing the sequence of pages viewed within each session | `website_pageview_id`, `created_at`, `website_session_id`, `pageview_url` |

### Analytical Approach

The analysis followed a three-step process aligned with the project objectives:

- **Filter the Data:** Isolate only the relevant traffic segment (`utm_source = 'gsearch'`, `utm_campaign = 'nonbrand'`) and test period (from the first appearance of `/lander-1` until July 28, 2012)

- **Calculate Bounce Rates:** For each session, identify the landing page (first pageview), count total pageviews, flag bounces (sessions with only 1 pageview), and aggregate bounce rates by landing page

- **Verify Significance:** Use statistical methods (confidence intervals) to determine if the observed improvement is statistically significant at the 95% confidence level

---

## 🔍 Analysis Process & Thinking

### Objective 1: Filtering the Data

**Goal:** Isolate only the data relevant to the A/B test for a fair comparison.

**My Thought Process:**

- I needed to understand **what** traffic was being tested (`gsearch` + `nonbrand`) and **when** the test started
- Finding the first occurrence of `/lander-1` marked the official test start date
- Any data before this date had to be excluded to avoid skewing results with pre-test behavior
- Joining the two tables was essential to create a complete dataset showing both **who** visited and **what** they viewed

**The Logic:**

- **Filter sessions:** gsearch + nonbrand 
- **Find test start:** first /lander-1 visit
- **Remove pre-test data:** sessions before test start
- **Join tables:** sessions + pageviews on session ID

**Key Insight:** A fair A/B test comparison requires identical conditions for both groups. By filtering only to the test period, I ensured that external factors (seasonality, marketing changes) didn't influence one group more than the other.

**SQL Approach:**

```sql
-- OBJECTIVE 1: Filter the Website Traffic

-- Use two sets of filters when joining tables:
    -- 1) date before 2012-07-28, utm_source = 'gsearch' and utm_campaign = 'nonbrand'
    -- 2) date after the A/B test start date, which is the first date where pageview_url = '/lander-1'
WITH filtered AS (
    SELECT 
        ws.website_session_id,
        ws.created_at AS session_start_time,
        wp.website_pageview_id,
        wp.created_at AS page_start_time,
        wp.pageview_url
    FROM website_sessions ws
    LEFT JOIN website_pageviews wp 
        ON ws.website_session_id = wp.website_session_id
    WHERE ws.created_at < '2012-07-28 00:00:00'
        AND ws.utm_source = 'gsearch'
        AND ws.utm_campaign = 'nonbrand'
        AND ws.created_at >= (
            SELECT MIN(created_at) 
            FROM website_pageviews
            WHERE pageview_url = '/lander-1'
        )
)
```

---

### Objective 2: Calculating Bounce Rates

**Goal:** Calculate bounce rates for each landing page to see if the new page performed better.

**Defining a "Bounce":**

A bounce occurs when a visitor views **only one page** during a session. If they explore even one additional page, it's not a bounce.

**My Thought Process:**

- For each session, I needed to identify:
  - The **landing page** (first pageview)
  - The **total pageviews** (did they explore further?)
- A session is a "bounce" if `total_pageviews = 1`
- Bounce rate = `bounced_sessions / total_sessions`

**The Logic:**

For each session:
- Find **first pageview** → **landing page**
- Count **total pageviews**
- **Flag as bounce** if **total = 1**
- Group by **landing page**
- Calculate **bounce rate**

**Key Insight:** The landing page is the **first interaction**, regardless of what pages come later. Even if a user eventually reaches the homepage, it's the landing page that **"captured"** them (or failed to). This is why we look at **first pageviews**, not home page visits specifically.

**SQL Approach:**

```sql
-- OBJECTIVE 2: Calculate the Bounce Rates

-- Step 1: Find landing page & total page views for each session
session_info AS (
    SELECT 
        website_session_id, 
        pageview_url, 
        ROW_NUMBER() OVER(PARTITION BY website_session_id 
                          ORDER BY page_start_time) AS page_view_rank,
        COUNT(website_pageview_id) OVER(PARTITION BY website_session_id) 
            AS total_page_views
    FROM filtered
),

-- Extract only the landing page (first pageview) for each session
for_bounce AS (
    SELECT 
        website_session_id, 
        pageview_url AS landing_page, 
        total_page_views 
    FROM session_info
    WHERE page_view_rank = 1
    ORDER BY website_session_id
),

-- Step 2: Flag bounce (1 if only 1 pageview, 0 otherwise)
bounce_flag AS (
    SELECT 
        *, 
        CASE WHEN total_page_views = 1 THEN 1 ELSE 0 END AS bounced
    FROM for_bounce
),

-- Step 3: Calculate bounce rate for each landing page
bounce_rate_calculation AS (
    SELECT 
        landing_page, 
        SUM(bounced) AS bounced_sessions, 
        COUNT(website_session_id) AS sessions,
        SUM(bounced) / COUNT(website_session_id) AS bounce_rate
    FROM bounce_flag 
    GROUP BY landing_page
)
```

**Results:**

| Landing Page | Total Sessions | Bounced Sessions | Bounce Rate |
|-------------------|--------------------|-------------------------|------------------|
| `/home` (Old) | 2,261 | 1,319 | 58.34% |
| `/lander-1` (New) | 2,315 | 1,232 | 53.22% |

**Initial Insight:** The new landing page shows a promising **5.12% absolute improvement** in bounce rate. But is this improvement real or just random chance?

---

### Objective 3: Verifying Statistical Significance

**Goal:** Determine if the improvement is statistically significant using a confidence interval.

**Why This Matters:**

A difference of 5.12% looks impressive, but with limited sample sizes, it could be due to random variation. Statistical analysis tells us if the improvement is **real** or if it could have happened by chance.

**My Thought Process:**

- We need to construct a **95% confidence interval** around the difference in bounce rates
- If the interval **does not contain zero**, we can be confident the difference is real
- The interval gives us a **range** of plausible values for the true difference

**The Statistical Framework:**

- **Point Estimate:** The observed difference between bounce rates
   - `p_new - p_old = 0.5322 - 0.5834 = -0.0512` (new page is 5.12% better)

- **Standard Error:** Measures how much the estimate might vary
   - `SE = sqrt[(p_old * (1-p_old) / n_old) + (p_new * (1-p_new) / n_new)]`

- **Critical Value:** For 95% confidence, `Z = 1.96`

- **Margin of Error:** How much "error" to allow
   - `ME = Critical Value * Standard Error`

- **Confidence Interval:** The range of plausible true differences
   - `CI = Point Estimate ± Margin of Error`

**SQL Approach:**

```sql
-- OBJECTIVE 3: Verify Statistical Significance

-- Step 1: Add column `1-p`, and label sample size 
-- for control group (old home page) and test group (new home page) 
cal_prep AS (
    SELECT 
        landing_page, 
        bounced_sessions, 
        sessions AS n_sample_size, 
        bounce_rate AS p, 
        (1 - bounce_rate) AS `1-p`
    FROM bounce_rate_calculation
),

-- Step 2: Calculate point estimate
cal_point_estimate AS (
    SELECT 
        cp1.landing_page AS landing_page1, 
        cp1.p AS p1, 
        cp2.landing_page AS landing_page2, 
        cp2.p AS p2
    FROM cal_prep cp1
    LEFT JOIN cal_prep cp2 
    ON cp1.landing_page <> cp2.landing_page
),

point_estimate_output AS (
    SELECT (p1 - p2) AS point_estimate
    FROM cal_point_estimate
    WHERE landing_page1 > landing_page2
),

-- Step 3: Calculate standard error 
standard_error_prep AS (
    SELECT 
        MAX(CASE WHEN landing_page = '/home' THEN n_sample_size END) AS n_old,
        MAX(CASE WHEN landing_page = '/lander-1' THEN n_sample_size END) AS n_new, 
        MAX(CASE WHEN landing_page = '/home' THEN p END) AS p_old,
        MAX(CASE WHEN landing_page = '/lander-1' THEN p END) AS p_new
    FROM cal_prep
),

standard_error_output AS (
    SELECT 
        SQRT((p_old * (1 - p_old) / n_old) + (p_new * (1 - p_new) / n_new)) AS standard_error
    FROM standard_error_prep
),

-- Step 4: Calculate margin of error through "critical value * standard error"
-- and calculate the confidence interval with its lower and upper bounds
interval_output AS (
    SELECT 
        1.96 * se.standard_error AS margin_of_error,
        pe.point_estimate - 1.96 * se.standard_error AS lower_bound,
        pe.point_estimate + 1.96 * se.standard_error AS upper_bound
    FROM point_estimate_output pe
    CROSS JOIN standard_error_output se
)

-- Step 5: Interpret the results
SELECT CASE 
    WHEN lower_bound < 0 AND upper_bound < 0 
        THEN 'We can be 95% confident that the new page has a lower bounce rate than the original.'
    WHEN lower_bound > 0 AND upper_bound > 0 
        THEN 'We can be 95% confident that the new page has a higher bounce rate than the original.'
    ELSE 'We cannot be 95% confident that there is a real difference between the two pages. The confidence interval contains 0.' 
END AS conclusion
FROM interval_output;
```

### Results

| Metric | Value |
|--------|-------|
| **Point Estimate** (Difference) | -5.12% |
| **Standard Error** | 0.015 |
| **Margin of Error** | 0.029 (2.9%) |
| **95% Confidence Interval** | [-7.99%, -2.25%] |

### Interpretation

- The confidence interval is **entirely below zero** (from -7.99% to -2.25%)
- It does **not contain zero**
- We can be **95% confident** that the new landing page reduces bounce rates by **2.25% to 7.99%** (95% CI: -7.99% to -2.25%) compared to the original homepage.

### Conclusion

✅ **Statistically Significant Improvement**

The analysis provides **strong evidence** that the **new landing page (`/lander-1`) outperforms the original homepage (`/home`)** in reducing bounce rates. Since **the entire 95% confidence interval falls below zero**, we can confidently **reject** the possibility that the observed improvement is due to random chance. This means:

- The new page is **genuinely more effective** at engaging visitors
- The improvement is **statistically significant** at the 95% confidence level
- We can recommend **implementing the new landing page** with confidence, knowing the positive impact on bounce rates is real and measurable

In practical terms, the new page reduces bounce rates by approximately 2.25% to 7.99% compared to the original, **meaning more visitors are staying on the site to explore products and potentially make purchases**.

---

## 💡 Key Findings & Business Recommendations

### Confirmed Improvement

The new landing page (`/lander-1`) outperforms the original homepage (`/home`):

- **Bounce Rate Reduction:** From 58.34% to 53.22% (≈5.12 percentage point improvement)
- **Statistical Confidence:** 95% confident the true improvement is between -7.99% and -2.25%
- **Real Business Impact:** For every 100,000 sessions, approximately 5,120 additional visitors are now engaging with the site instead of bouncing

### Is a 5.12% Improvement Meaningful?

While statistically significant, the business impact requires context:

**Industry Benchmarks:**
- **Average e-commerce bounce rate** ranges from **20% to 45%** (Leadpages, 2025)
- A **5% improvement** is considered **modest but meaningful**
- For a **58% baseline, reducing to 53%** is a **positive signal but not transformational**

**Revenue Impact Estimate (per 100K sessions):**

| Metric | Before | After | Impact |
|----------|----------|---------|----------|
| Engaged Visitors | 41,660 | 46,780 | +5,120 |
| Estimated Revenue* | $62,490 | $70,170 | +$7,680 |

*Assuming 3% conversion rate and $50 average order value*

**Key Insight:** The new page is a step in the right direction, but not a game-changer. The core business challenge remains: **We need to understand what drives visitors to not just stay, but to buy.**

### Critical Questions for Follow-Up Validation

The reduced bounce rate proves the new design **attracts customers to stay longer**, but this does not guarantee revenue generation. The following must be validated:

**Key Questions:**

- **Do lower bounce rates translate to more orders?** Compare conversion rates between old and new pages
- **What drives users to proceed to other pages?** Is it the new design, ads, links, or genuine product interest?
- **What is the quality of engagement?** Are visitors exploring products or just clicking randomly?

---

## 🚀 Broader Implications & Next Steps

### What This Means for the Business

- The new page design could **benefit other traffic sources (`bsearch`, brand campaigns)** and should be tested on each before full rollout
- Design principles (clear value proposition, prominent CTAs, cleaner layout) could improve other pages **across the site**
- This test validates **data-driven experimentation** and establishes a **framework** for future A/B tests

### Potential Next Steps

#### Revenue Impact Analysis

- Compare **conversion rates (sessions → purchases)** between landing pages
- Calculate **revenue per session** for each group

#### Customer Quality Assessment

- Analyze refund rates
- Check if the new page attracts **higher-quality customers**
- Measure **customer lifetime value**

#### Segmentation Deep Dive

- Break down results by **device type (desktop vs. mobile)**
- Compare **repeat vs. new visitors**
- Analyze performance by **traffic source**

#### Product Affinity Analysis

- Identify which products are most popular from each landing page
- Optimize **product recommendations** based on entry point

These analyses would complete the picture, showing not just engagement improvement, but the actual revenue impact of the new landing page.

---

## 📚 References

Leadpages. (2025, May 30). *Understand your bounce rate: Key insights*. https://www.leadpages.com/blog/average-bounce-rate

---

## 📁 Files in This Repository

- `abtest.sql` # Complete SQL analysis script
- `README.md` # Project overview and analysis

---

## 🏷️ Tags

`#SQL` `#ABTesting` `#StatisticalAnalysis` `#ConfidenceInterval` `#BounceRate` `#DataAnalysis` `#CTE` `#WindowFunctions` `#Joins` `#DataDrivenDecisionMaking` `#Ecommerce` `#MavenAnalytics` `#PortfolioProject`
