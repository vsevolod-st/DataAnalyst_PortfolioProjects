/* Цель проекта: 
 * познакомиться с ключевыми таблицами 'users' и 'events';
 * изучить влияние характеристик игроков их игровых персонажей на покупку внутриигровой валюты; 
 * оценить активность игроков при совершении внутриигровых покупок.
*/

---- Часть 1. Разведочный анализ данных

-- Задача 1. Информация о таблицах в схеме 'fantasy'
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'fantasy';

-- Задача 2. Данные в таблице 'users'
SELECT
	t1.table_schema,
	t1.table_name,
	t1.column_name,
	t1.data_type,
	t2.constraint_name
FROM information_schema.COLUMNS AS t1 
LEFT JOIN information_schema.key_column_usage AS t2 USING(table_schema, table_name, column_name)
WHERE t1.table_schema = 'fantasy' AND t1.table_name = 'users';

-- Задача 3. Вывод первых строк таблицы 'users'
SELECT *,
    COUNT(*) OVER() AS row_count
FROM fantasy.users
LIMIT 5;

-- Задача 4. Проверка пропусков в таблице 'users'
SELECT
	COUNT(*) AS row_count
FROM fantasy.users
WHERE 
	class_id IS NULL OR
	ch_id IS NULL OR
	pers_gender IS NULL OR
	server IS NULL OR
	race_id IS NULL OR
	payer IS NULL OR
	loc_id IS NULL;

-- Задача 5. Знакомство с категориальными данными таблицы 'users'
SELECT 
	server,
	COUNT(*) AS row_count
FROM fantasy.users
GROUP BY server;

-- Задача 6. Знакомство с таблицей 'events'
SELECT 
	c.table_schema,
	c.table_name,
	c.column_name,
	c.data_type,
	k.constraint_name
FROM information_schema.columns AS c 
LEFT JOIN information_schema.key_column_usage AS k 
	USING(table_name, column_name, table_schema)
WHERE c.table_schema = 'fantasy' AND c.table_name = 'events'
ORDER BY c.table_name;

-- Задача 7. Выведите первые пять строк таблицы 'events'
SELECT *,
	COUNT(*) OVER() AS row_count
FROM fantasy.events
LIMIT 5;

-- Задача 8. Проверка пропусков в таблице 'events'
SELECT COUNT(*) row_count
FROM fantasy.events
WHERE
	date IS NULL OR
	time IS NULL OR
	amount IS NULL OR
	seller_id IS NULL;

-- Задача 9. Изучаем пропуски в таблице 'events'
SELECT 
	COUNT(date) AS data_count,
	COUNT(time) AS data_time,
	COUNT(amount) AS data_amount,
	COUNT(seller_id) AS data_seller_id
FROM fantasy.events
WHERE
	date IS NULL OR
	time IS NULL OR
	amount IS NULL OR
	seller_id IS NULL;


---- Часть 2. Исследовательский анализ данных

-- Задача 1. Исследование доли платящих игроков
-- 1.1. Доля платящих пользователей по всем данным:
SELECT 
	COUNT(id) AS count_all_user,
	SUM(payer) AS count_pay_user,
	ROUND(SUM(payer::numeric) / COUNT(id) * 100, 2) AS share_pay_user
FROM fantasy.users;

-- 1.2. Доля платящих пользователей в разрезе расы персонажа:
SELECT 
	rc.race,
	SUM(us.payer) AS count_pay_user,
	COUNT(us.id) AS count_all_user,
	ROUND(SUM(us.payer::numeric) / COUNT(us.id) * 100, 2) AS share_pay_user
FROM fantasy.users AS us
LEFT JOIN fantasy.race AS rc USING(race_id)
GROUP BY rc.race
ORDER BY count_all_user DESC;

-- Задача 2. Исследование внутриигровых покупок
-- 2.1. Статистические показатели по полю amount:
SELECT
	COUNT(*) AS count_event,
	SUM(amount::numeric) AS total_amount,
	MIN(amount) AS min_amount,
	MAX(amount) AS max_amount,
	ROUND(AVG(amount::numeric), 2) AS avg_amount,
	PERCENTILE_DISC(0.50) WITHIN GROUP (ORDER BY amount) AS median_amount,
	ROUND(STDDEV(amount::numeric), 2) AS stand_dev_amount
FROM fantasy.events;

-- 2.2: Аномальные нулевые покупки:
SELECT
	(SELECT COUNT(*) FROM fantasy.events) AS total_event,
	COUNT(*) AS count_zero_cost,
	COUNT(*)::float / (SELECT COUNT(*) FROM fantasy.events)::float AS share_zero_cost
FROM fantasy.events
WHERE amount = 0;

-- 2.3: Сравнительный анализ активности платящих и неплатящих игроков:
SELECT
	CASE
		WHEN us.payer = 1 THEN 'Платящие игроки'
		ELSE 'Неплатящие игроки'
	END AS payer,
	COUNT(DISTINCT us.id) AS count_pay_user,
	ROUND(COUNT(ev.transaction_id)::numeric / COUNT(DISTINCT us.id), 0) AS avg_count_event,
	ROUND(SUM(ev.amount::numeric) / COUNT(DISTINCT us.id), 2) AS avg_amount_user
FROM fantasy.users AS us 
LEFT JOIN fantasy.events AS ev USING(id)
WHERE ev.amount > 0
GROUP BY us.payer;

-- 2.4: Популярные эпические предметы:
WITH
	table1 AS(
	SELECT
		itm.item_code AS epic_item_id,
		itm.game_items AS epic_item_name,
		COUNT(evnt.transaction_id) AS count_event,
		COUNT(DISTINCT evnt.id) AS count_user
	FROM fantasy.events AS evnt
	JOIN fantasy.items AS itm USING(item_code)
	WHERE evnt.amount > 0
	GROUP BY itm.item_code, itm.game_items
)
SELECT
	epic_item_id,
	epic_item_name,
	count_event,
	ROUND((count_event::numeric / SUM(count_event) OVER()) * 100, 2) AS share_event,
	ROUND(count_user::numeric / (SELECT COUNT(DISTINCT id) FROM fantasy.events) * 100, 2) AS share_buy_user
FROM table1
ORDER BY count_event DESC;

---- Часть 3. Решение ad hoc-задач

-- Задача 1. Зависимость активности игроков от расы персонажа:
WITH
	table1 AS(
	SELECT
		us.race_id,
		COUNT(DISTINCT ev.id) AS count_pay_user
	FROM fantasy.events AS ev 
	LEFT JOIN fantasy.users AS us USING(id)
	WHERE ev.amount > 0 AND us.payer = 1
	GROUP BY us.race_id
),	
	table2 AS(
	SELECT
		us.race_id,
		rc.race,
		COUNT(DISTINCT us.id) AS count_total_user,
		COUNT(DISTINCT ev.id) AS count_buy_user, 
		COUNT(DISTINCT ev.transaction_id) AS total_event,
		SUM(ev.amount::numeric) AS total_amount
	FROM fantasy.users AS us
	LEFT JOIN fantasy.events AS ev ON ev.id = us.id AND ev.amount > 0
	LEFT JOIN fantasy.race AS rc ON rc.race_id = us.race_id
	GROUP BY us.race_id, rc.race
)
SELECT
	race,
	count_total_user,
	count_buy_user,
	ROUND(count_buy_user::numeric / count_total_user * 100, 2) AS share_buy_of_total_user,
	ROUND(t1.count_pay_user::numeric / count_buy_user * 100, 2) AS share_pay_of_buy_user,
	ROUND(total_event::numeric / count_buy_user, 0) AS avg_event,
	ROUND(total_amount::numeric / total_event, 2) AS avg_amount_event,
	ROUND(total_amount::numeric / count_buy_user, 2) AS avg_amount_user
FROM table2
LEFT JOIN table1 AS t1 USING(race_id)
ORDER BY count_total_user DESC;

-- Задача 2: Частота покупок
WITH
	table1 AS(
	SELECT
		ev.id,
		ev.transaction_id,
		MAX(date::date) OVER(PARTITION BY ev.id) - MIN(date::date) OVER(PARTITION BY ev.id) AS duration_day,
		us.payer
	FROM fantasy.events AS ev
	LEFT JOIN fantasy.users AS us USING (id)
	WHERE ev.amount > 0
), table2 AS(
	SELECT
		id,
		COUNT(transaction_id) AS count_event,
		duration_day,
		ROUND(duration_day::numeric / (COUNT(transaction_id) - 1), 2) AS avg_duration_day,
		payer
	FROM table1
	GROUP BY id, payer, duration_day
), table3 AS(
	SELECT *,
		NTILE(3) OVER(ORDER BY avg_duration_day) AS ranc_dur
	FROM table2
	WHERE count_event >= 25
)
SELECT
	CASE
		WHEN ranc_dur = 1 THEN 'высокая частота'
		WHEN ranc_dur = 2 THEN 'умеренная частота'
		WHEN ranc_dur = 3 THEN 'низкая частота'
	END AS ranc_duration,
	COUNT(id) AS  count_buy_user,
	SUM(payer) AS count_pay_user,
	ROUND(SUM(payer::numeric) / COUNT(id) * 100, 2) AS share_pay_of_buy_user,
	ROUND(AVG(count_event::numeric), 0) AS avg_count_event,
	ROUND(AVG(avg_duration_day::numeric), 2) AS avg_duration_day
FROM table3
GROUP BY ranc_dur
ORDER BY ranc_dur;