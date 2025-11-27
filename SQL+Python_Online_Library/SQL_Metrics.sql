/*
1. Расчёт MAU авторов
Определить количество уникальных пользователей в месяц, которые читали 
или слушали конкретного автора. 
Вывести имена топ-3 авторов с наибольшим MAU в ноябре и сами значения MAU.
*/

SELECT
    atr.main_author_name,
    COUNT(DISTINCT aud.puid) AS mau
FROM audition AS aud
LEFT JOIN content AS cnt ON cnt.main_content_id = aud.main_content_id
LEFT JOIN author AS atr ON atr.main_author_id = cnt.main_author_id
WHERE 
    EXTRACT(MONTH FROM aud.msk_business_dt_str::date) = 11 
GROUP BY main_author_name
ORDER BY mau DESC
LIMIT 3;

-- Вывод:

/*
|main_author_name	|mau	|
|-------------------|-------|
|Андрей Усачев		|7107	|
|Лиана Шнайдер		|3338	|
|Игорь Носов		|3063	|
*/

------------------------------------------------------------------------------------
/*
2. Расчёт MAU произведений
Определить количество уникальных пользователей в месяц которые читали 
или слушали конкретное произведение.
Вывести названия топ-3 произведений с наибольшим MAU в ноябре, 
а также списки жанров этих произведений, их авторов и сами значения MAU
*/

SELECT 
    cnt.main_content_name,
    cnt.published_topic_title_list,
    atr.main_author_name,
    COUNT(DISTINCT aud.puid) AS mau
FROM audition AS aud
LEFT JOIN content AS cnt ON cnt.main_content_id = aud.main_content_id
LEFT JOIN author AS atr ON atr.main_author_id = cnt.main_author_id
WHERE 
    EXTRACT(MONTH FROM aud.msk_business_dt_str::date) = 11 
GROUP BY main_content_name, published_topic_title_list, main_author_name
ORDER BY mau DESC
LIMIT 3;

-- Вывод:

/*
|main_content_name						 |published_topic_title_list								|main_author_name	|mau	|
|----------------------------------------|----------------------------------------------------------|-------------------|-------|
|Собачка Соня на даче					 |['Детская проза и поэзия', 'Аудио']						|Андрей Усачев		|4597	|
|Женькин клад и другие школьные рассказы |['Сказки и фольклор', 'Детская проза и поэзия', 'Аудио']	|Игорь Носов		|3050	|
|Знаменитая собачка Соня				 |['Аудиоспектакли', 'Детская проза и поэзия', 'Аудио']		|Андрей Усачев		|2785	|
*/

------------------------------------------------------------------------------------
/*
3. Расчёт Retention Rate
Проанализировать ежедневный Retention Rate всех пользователей, которые были активны 2 декабря.
Рассчитать ежедневный Retention Rate пользователей до конца представленных данных.
*/

WITH users_base AS(
    SELECT DISTINCT puid
    FROM audition
    WHERE msk_business_dt_str = '2024-12-02'
	), 
	active_users AS (
    SELECT 
        DISTINCT msk_business_dt_str::date, 
        puid
    FROM audition
    WHERE msk_business_dt_str::date >= '2024-12-02'
	),
	daily_retention AS(
    SELECT
        us.puid,
        aus.msk_business_dt_str - '2024-12-02'::date AS day_since_install
    FROM users_base AS us
    JOIN active_users AS aus ON aus.puid = us.puid
)
SELECT
    day_since_install,
    COUNT(DISTINCT puid) AS retained_users,
    ROUND(1.0 * COUNT(DISTINCT puid) / MAX(COUNT(DISTINCT puid)) OVER(), 2) AS retention_rate
FROM daily_retention
GROUP BY day_since_install
ORDER BY day_since_install;

-- Вывод:

/*
|day_since_install	|retained_users	|retention_rate	|
|-------------------|---------------|---------------|
|0					|4259			|1				|
|1					|2698			|0.63			|
|2					|2550			|0.6			|
|3					|2421			|0.57			|
|4					|2231			|0.52			|
|5					|1994			|0.47			|
|6					|2129			|0.5			|
|7					|2287			|0.54			|
|8					|2274			|0.53			|
|9					|2207			|0.52			|
*/

------------------------------------------------------------------------------------
/*
4. Расчёт LTV
Рассчитать средние LTV для пользователей в Москве и Санкт-Петербурге. 
Вывести общее количество пользователей в каждом городе и их средний LTV.
Стоимость подписки составляет 399 руб. Будем считать, что пользователь 
приносит 399 рублей, если хотя бы раз в месяц пользуется сервисом.
*/

WITH table1 AS(
    SELECT
        geo.usage_geo_id_name AS city,
        aud.puid,
        COUNT(DISTINCT (DATE_TRUNC('month', msk_business_dt_str::date))) * 399 AS ltv
    FROM audition AS aud
    JOIN geo AS geo ON geo.usage_geo_id = aud.usage_geo_id
    WHERE geo.usage_geo_id_name IN ('Москва', 'Санкт-Петербург')
    GROUP BY city, puid
)
SELECT
    city,
    COUNT(puid) AS total_users,
    ROUND(AVG(ltv), 2) AS ltv
FROM table1
GROUP BY city;

-- Вывод:

/*
|city				|total_users	|ltv	|
|-------------------|---------------|-------|
|Москва				|16808			|764.55	|
|Санкт-Петербург	|12559			|731.82	|
*/

------------------------------------------------------------------------------------
/*
5. Расчёт средней выручки прослушанного часа (средний чек)
Рассчитать ежемесячную среднюю выручку от часа чтения или прослушивания 
(выручка (MAU * 399 рублей) / сумма прослушанных часов.). 
Рассчитать эту метрику вместе с MAU и суммой прослушанных часов с сентября по ноябрь.
*/

SELECT
    DATE_TRUNC('MONTH', msk_business_dt_str::date)::date AS month_b,
    COUNT(DISTINCT puid) AS mau,
    ROUND(SUM(hours::numeric), 2) AS hours,
    ROUND(COUNT(DISTINCT puid) * 399 / SUM(hours::numeric), 2) AS avg_hour_rev
FROM audition
WHERE EXTRACT(MONTH FROM msk_business_dt_str::date) BETWEEN 9 AND 11
GROUP BY month_b;

-- Вывод:

/*
|month		|mau	|hours	|avg_hour_rev	|
|-----------|-------|-------|---------------|
|2024-09-01	|16320	|105539	|61.7			|
|2024-10-01	|18280	|137384	|53.09			|
|2024-11-01	|18594	|145351	|51.04			|
*/

------------------------------------------------------------------------------------