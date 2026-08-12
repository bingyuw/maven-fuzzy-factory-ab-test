-- Create database
USE `a/b test`;

-- Create table website_sessions
CREATE TABLE website_sessions (
	website_session_id INT PRIMARY KEY,
    created_at VARCHAR(50),
    user_id INT,
    is_repeat_session INT,
    utm_source VARCHAR(50),
    utm_campaign VARCHAR(50),
    utm_content VARCHAR(50),
    device_type VARCHAR(50),
    http_referer VARCHAR(100)
);

-- Load data into table website_sessions
LOAD DATA INFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/website_sessions.csv'
INTO TABLE website_sessions
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS; 

-- Create table website_pageviews 
CREATE TABLE website_pageviews (
	website_pageview_id INT PRIMARY KEY,
    created_at VARCHAR(50),
    website_session_id INT,
    pageview_url VARCHAR(100)
);

-- Load data into table website_pageviews
LOAD DATA INFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/website_pageviews.csv'
INTO TABLE website_pageviews
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS; 

-- Change the `created_at` from string to date in table website_pageviews
SET SQL_SAFE_UPDATES = 0;
UPDATE website_pageviews
SET created_at = STR_TO_DATE(created_at, '%Y-%m-%d %H:%i:%s');
SET SQL_SAFE_UPDATES = 1;

-- Change the `created_at` from string to date in table website_sessions
SET SQL_SAFE_UPDATES = 0;
UPDATE website_sessions
SET created_at = STR_TO_DATE(created_at, '%Y/%m/%d %H:%i');
SET SQL_SAFE_UPDATES = 1;

-- OBJECTIVE 1: Filter the Website Traffic
-- Use two sets of filters when joining tables:
	-- 1) date before 2012-07-28, utm_source = 'gsearch' and utm_campaign = 'nonbrand'
    -- 2) date after the A/B test start date, which is the first date where pageview_url = '/lander-1'
WITH filtered AS (
	SELECT ws.website_session_id, ws.created_at AS session_start_time, ws.user_id, ws.is_repeat_session,
    ws.utm_source, ws.utm_campaign, ws.utm_content, ws.device_type, ws.http_referer,
    wp.website_pageview_id, wp.created_at AS page_start_time, wp.pageview_url
	FROM website_sessions ws 
	LEFT JOIN website_pageviews wp
	ON ws.website_session_id = wp.website_session_id
	WHERE ws.created_at < '2012-07-28 00:00:00'
	AND ws.utm_source = 'gsearch'
	AND ws.utm_campaign = 'nonbrand'
	AND ws.created_at >= (
		SELECT MIN(created_at) 
		FROM website_pageviews
		WHERE pageview_url = '/lander-1'))
,
-- OBJECTIVE 2: Calculate the Bounce Rates
-- Step 1: Find landing page & total page views for each session
session_info AS (
	SELECT website_session_id, pageview_url, 
	ROW_NUMBER()OVER(PARTITION BY website_session_id ORDER BY page_start_time) AS page_view_rank,
	COUNT(website_pageview_id)OVER(PARTITION BY website_session_id) AS total_page_views
	FROM filtered)
,
-- Extract only the landing page (first pageview) for each session
for_bounce AS (
	SELECT website_session_id, pageview_url AS landing_page, total_page_views 
	FROM session_info
	WHERE page_view_rank = 1
	ORDER BY website_session_id)
,
-- Step 2: Flag bounce (1 if only 1 pageview, 0 otherwise)
bounce_flag AS (
	SELECT *, CASE WHEN total_page_views = 1 THEN 1 ELSE 0 END AS bounced
	FROM for_bounce)
,
-- Step 3: Calculate bounce rate for each landing page
bounce_rate_calculation AS (
	SELECT landing_page, 
	SUM(bounced) AS bounced_sessions, 
	COUNT(website_session_id) AS sessions,
	SUM(bounced)/COUNT(website_session_id) AS bounce_rate
	FROM bounce_flag 
	GROUP BY landing_page)
,
-- OBJECTIVE 3: Verifying Statistical Significance
-- Step 1: Add column `1-p`, and label sample size 
-- for control group (old home page) and test group (new home page) 
cal_prep AS (
	SELECT landing_page, bounced_sessions, sessions AS n_sample_size, 
	bounce_rate AS p, (1-bounce_rate) AS `1-p`
	FROM bounce_rate_calculation)
,
-- Step 2: Calculate point estimate
cal_point_estimate AS (
	SELECT cp1.landing_page AS landing_page1, cp1.p AS p1, cp2.landing_page AS landing_page2, cp2.p AS p2
	FROM cal_prep cp1
	LEFT JOIN cal_prep cp2 
	ON cp1.landing_page <> cp2.landing_page)
,
point_estimate_output AS (
	SELECT (p1-p2) AS point_estimate
	FROM cal_point_estimate
	WHERE landing_page1 > landing_page2) 
,
-- Step 3: Calculate standard error 
standard_error_prep AS (
	SELECT 
		MAX(CASE WHEN landing_page = '/home' THEN n_sample_size END) AS n_old,
		MAX(CASE WHEN landing_page = '/lander-1' THEN n_sample_size END) AS n_new, 
		MAX(CASE WHEN landing_page = '/home' THEN p END) AS p_old,
		MAX(CASE WHEN landing_page = '/lander-1' THEN p END) AS p_new
	FROM cal_prep)
,
standard_error_output AS (
	SELECT 
		SQRT((p_old * (1 - p_old) / n_old) + (p_new * (1-p_new) / n_new)) AS standard_error
	FROM standard_error_prep)
,
-- Step 4: Calculate margin of error through "critical value * standard error"
-- and calculate the confidence interval with its lower and upper bounds
interval_output AS (
	SELECT 
		1.96 * se.standard_error AS margin_of_error,
		pe.point_estimate - 1.96 * se.standard_error AS lower_bound,
		pe.point_estimate + 1.96 * se.standard_error AS upper_bound
	FROM point_estimate_output pe
	CROSS JOIN standard_error_output se) 
-- Step 5: Interpret the results
SELECT CASE 
	WHEN lower_bound < 0 AND upper_bound < 0 THEN 'We can be 95% confident that the new page has a lower bounce rate than the original.'
	WHEN lower_bound > 0 AND upper_bound > 0 THEN 'We can be 95% confident that the new page has a higher bounce rate than the original.'
    ELSE 'We cannot be 95% confident that there is a real difference between the two pages. The confidence interval contains 0.' END AS conclusion
FROM interval_output 