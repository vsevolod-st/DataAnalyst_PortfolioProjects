/* 
1. Время активности объявлений

Задача: определить — по времени активности объявления — самые привлекательные 
для работы сегменты недвижимости Санкт-Петербурга и городов ЛО

Вопросы: 
- 	Какие сегменты рынка недвижимости Санкт-Петербурга и городов ЛО имеют наиболее 
	короткие или длинные сроки активности объявлений?
-	Какие характеристики недвижимости, включая площадь недвижимости, 
	среднюю стоимость квадратного метра, количество комнат и балконов 
	и другие параметры, влияют на время активности объявлений? 
	Как эти зависимости варьируют между регионами?
-	Есть ли различия между недвижимостью Санкт-Петербурга и ЛО по полученным результатам?
*/ 

WITH
--	Рассчитываем стоимость 1 кв.м. для каждого объявления
	price_1m2 AS (
	SELECT 
		f.id AS p1m_id,
		ROUND(a.last_price::numeric / f.total_area::numeric, 2) AS price_1m 
	FROM real_estate.flats AS f 
	JOIN real_estate.advertisement AS a ON a.id = f.id
),	
--	Определяем аномальные значения (выбросы) по 1 и 99 перцентилям:
	limits AS(
	SELECT
		PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY p.price_1m) AS price_1m_limit_h,
		PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY p.price_1m) AS price_1m_limit_l,
		PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY f.total_area) AS total_area_limit,
		PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY f.rooms) AS rooms_limit,
		PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY f.balcony) AS balcony_limit,
		PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY f.ceiling_height) AS ceiling_height_limit_h,
		PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY f.ceiling_height) AS ceiling_height_limit_l
	FROM real_estate.flats AS f
	JOIN price_1m2 AS p ON p.p1m_id = f.id
), 
-- 	Создаем датасет без учета выбросов и активных объявлений, 
--	оставляем города, добавляем сегменты по регионам и срокам активности объявлений:
	dataset AS(
	SELECT *,
		a.first_day_exposition + a.days_exposition::int AS last_day_exposition,
		DATE_TRUNC('month', a.first_day_exposition)::date AS month_open_advertisement,
		DATE_TRUNC('month', a.first_day_exposition + a.days_exposition::int)::date AS month_closed_advertisement,
		CASE
			WHEN c.city = 'Санкт-Петербург' THEN 'Санкт-Петербург'
			ELSE 'Ленинградская область'
		END AS segment_region,
		CASE
			WHEN a.days_exposition <=30 THEN '1_до 1 месяца'
			WHEN a.days_exposition <=90 THEN '2_до 3 месяцев'
			WHEN a.days_exposition <=180 THEN '3_до 6 месяцев'
			WHEN a.days_exposition <=365 THEN '4_до 12 месяцев'
			ELSE '5_свыше 12 месяцев'
		END AS segment_period
	FROM real_estate.flats AS f
	JOIN real_estate.advertisement AS a ON a.id = f.id
	JOIN price_1m2 AS p ON p.p1m_id = f.id
	LEFT JOIN real_estate.city AS c ON c.city_id = f.city_id
	LEFT JOIN real_estate.type AS t ON t.type_id = f.type_id
	WHERE 
		-- Убираем выбросы
		p.price_1m < (SELECT price_1m_limit_h FROM limits)
		AND p.price_1m > (SELECT price_1m_limit_l FROM limits)
		AND (f.rooms < (SELECT rooms_limit FROM limits) OR f.rooms IS NULL)
		AND (f.balcony < (SELECT balcony_limit FROM limits) OR f.balcony IS NULL)
		AND ((f.ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
		AND f.ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR f.ceiling_height IS NULL)
		-- Оставляем только закрытый объявления
		AND a.days_exposition IS NOT NULL 
		-- Оставляем только города
		AND t.type = 'город'
)
-- 	Итоговый запрос с агрегированными данными по регионам и срокам активности объявлений
SELECT
	segment_region AS "Регион",
	segment_period AS "Длительность продажи",
	COUNT(*) AS "Количество квартир",
	SUM(is_apartment) AS "Количество апартаментов",
	ROUND(COUNT(*)::numeric / SUM(COUNT(*)) OVER(PARTITION BY segment_region) * 100, 2) AS "Доля объявлений",
	ROUND(AVG(price_1m), 2) AS "Стоимость 1 кв.м.",
	ROUND(AVG(total_area::numeric), 2) AS "Общая площадь",
	ROUND(AVG(rooms::numeric), 0) AS "Количество комнат",
	ROUND(AVG(balcony::numeric), 0) AS "Количество балконов",
	PERCENTILE_DISC(0.5) WITHIN GROUP(ORDER BY floors_total) AS "Этажность дома"	
FROM dataset
GROUP BY segment_region, segment_period
ORDER BY segment_region DESC, segment_period;

/* 
2. Сезонность объявлений

Задача: Проанализировать сезонные тенденции на рынке недвижимости Санкт-Петербурга 
и ЛО, чтобы выявить периоды с повышенной активностью продавцов 
и покупателей недвижимости. 

Вопросы:
- 	В какие месяцы наблюдается наибольшая активность в публикации объявлений 
	о продаже недвижимости? А в какие — по снятию? 
	Это показывает динамику активности покупателей.
-	Совпадают ли периоды активной публикации объявлений и периоды 
	активной покупки недвижимости (по месяцам снятия объявлений)?
-	Как сезонные колебания влияют на среднюю стоимость квадратного метра 
	и среднюю площадь квартир? Что можно сказать о зависимости этих параметров от месяца?
*/

WITH
-- 	Рассчитываем стоимость 1 кв.м. для каждого объявления
	price_1m2 AS (
	SELECT 
		f.id AS p1m_id, 
		ROUND(a.last_price::numeric / f.total_area::numeric, 2) AS price_1m 
	FROM real_estate.flats AS f 
	JOIN real_estate.advertisement AS a ON a.id = f.id
),	
-- 	Определяем аномальные значения (выбросы) по 1 и 99 перцентилям:
	limits AS(
	SELECT
		PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY p.price_1m) AS price_1m_limit_h,
		PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY p.price_1m) AS price_1m_limit_l,
		PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY f.total_area) AS total_area_limit,
		PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY f.rooms) AS rooms_limit,
		PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY f.balcony) AS balcony_limit,
		PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY f.ceiling_height) AS ceiling_height_limit_h,
		PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY f.ceiling_height) AS ceiling_height_limit_l
	FROM real_estate.flats AS f
	JOIN price_1m2 AS p ON p.p1m_id = f.id
), 
-- 	Создаем датасет без учета выбросов, фильтруем города, добавляем дополнительные поля:
	dataset AS(
	SELECT 
		a.first_day_exposition,
		a.days_exposition,
		a.first_day_exposition + a.days_exposition::int AS last_day_exposition,
		EXTRACT(MONTH FROM a.first_day_exposition) AS month_open_advertisement,
		EXTRACT(MONTH FROM (a.first_day_exposition + a.days_exposition::int)) AS month_closed_advertisement,
		f.total_area,
		p.price_1m
	FROM real_estate.flats AS f
	JOIN real_estate.advertisement AS a ON a.id = f.id
	JOIN price_1m2 AS p ON p.p1m_id = f.id
	LEFT JOIN real_estate.city AS ct ON ct.city_id = f.city_id
	LEFT JOIN real_estate.type AS t ON t.type_id = f.type_id
	WHERE 
		p.price_1m < (SELECT price_1m_limit_h FROM limits)
		AND p.price_1m > (SELECT price_1m_limit_l FROM limits)
		AND (f.rooms < (SELECT rooms_limit FROM limits) OR f.rooms IS NULL)
		AND (f.balcony < (SELECT balcony_limit FROM limits) OR f.balcony IS NULL)
		AND ((f.ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
		AND f.ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR f.ceiling_height IS NULL)
		AND t.type = 'город'
),
-- 	Анализируем продажу недвижимости за полные года 2015 - 2018
	sale_group_month AS(
	SELECT 
		month_open_advertisement,
		DENSE_RANK() OVER(ORDER BY COUNT(*) DESC) AS sale_rank,
		COUNT(*) AS sale_count_adv,
		ROUND(AVG(price_1m::numeric), 2) AS sale_avg_price_1m,
		ROUND(AVG(total_area::numeric), 2) AS sale_avg_area		
	FROM dataset
	WHERE EXTRACT(YEAR FROM first_day_exposition) BETWEEN 2015 AND 2018
	GROUP BY month_open_advertisement
	ORDER BY month_open_advertisement
), 
-- 	Анализируем покупку недвижимости за полные года 2017 - 2018
	buy_group_month AS(
	SELECT 
		month_closed_advertisement,
		DENSE_RANK() OVER(ORDER BY COUNT(*) DESC) AS buy_rank,
		COUNT(*) AS buy_count_adv,
		ROUND(AVG(price_1m::numeric), 2) AS buy_avg_price_1m,
		ROUND(AVG(total_area::numeric), 2) AS buy_avg_area		
	FROM dataset
	WHERE 
		EXTRACT(YEAR FROM last_day_exposition) BETWEEN 2017 AND 2018
		AND days_exposition IS NOT NULL -- убираем активные объявления
	GROUP BY month_closed_advertisement
	ORDER BY month_closed_advertisement
)
-- 	Собираем итоговую таблицу. 
--	Объединяем агрегированные показатели по продажам и покупкам для анализа
SELECT
	to_char(make_date(2000,month_open_advertisement::int,1), 'Month') AS "Месяц активности",
	sale_rank AS "Ранг количества объявлений",
	sale_count_adv AS "Количество объявлений",
	sale_avg_price_1m AS "Стоимость 1 кв.м.",
	sale_avg_area AS "Общая площадь",
	buy_rank AS "Ранг количества продаж",
	buy_count_adv AS "Количество продаж",
	buy_avg_price_1m AS "Стоимость 1 кв.м.",
	buy_avg_area AS "Общая площадь"
FROM sale_group_month AS s
JOIN buy_group_month AS b ON b.month_closed_advertisement = s.month_open_advertisement
ORDER BY month_open_advertisement;

/*
3. Анализ рынка недвижимости Ленобласти

Задача: Определить, в каких населённых пунктах Ленинградской области активнее всего 
продаётся недвижимость и какая именно. Так мы увидим, где стоит поработать, и учтем 
особенности Ленинградской области при принятии бизнес-решений.

Вопросы:
-	В каких населённых пунктах Ленинградской области наиболее активно публикуют 
	объявления о продаже недвижимости?
-	В каких населённых пунктах Ленинградской области самая высокая доля снятых 
	с публикации объявлений? Это может указывать на высокую долю продажи недвижимости.
-	Какова средняя стоимость одного квадратного метра и средняя площадь продаваемых квартир 
	в различных населённых пунктах? Есть ли вариация значений по этим метрикам?
-	Среди выделенных населённых пунктов какие населенные пункты выделяются 
	по продолжительности публикации объявлений?
*/

WITH
-- 	Рассчитываем стоимость 1 кв.м. для каждого объявления
	price_1m2 AS (
	SELECT 
		f.id AS p1m_id, 
		ROUND(a.last_price::numeric / f.total_area::numeric, 2) AS price_1m 
	FROM real_estate.flats AS f 
	JOIN real_estate.advertisement AS a ON a.id = f.id
),	
--	Определяем аномальные значения (выбросы) по 1 и 99 перцентилям:
	limits AS(
	SELECT
		PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY p.price_1m) AS price_1m_limit_h,
		PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY p.price_1m) AS price_1m_limit_l,
		PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY f.total_area) AS total_area_limit,
		PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY f.rooms) AS rooms_limit,
		PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY f.balcony) AS balcony_limit,
		PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY f.ceiling_height) AS ceiling_height_limit_h,
		PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY f.ceiling_height) AS ceiling_height_limit_l
	FROM real_estate.flats AS f
	JOIN price_1m2 AS p ON p.p1m_id = f.id
)
-- 	Создаем итоговый запрос. Отсеиваем выбросы, оставляем населенные пункты ЛО:
SELECT
	ct.city AS "Населенный пункт",
	COUNT(*) AS "Количество объявлений",
	ROUND(COUNT(*) FILTER(WHERE a.days_exposition IS NOT NULL)::numeric / COUNT(*) * 100, 2) AS "Доля закрытых объявлений",
	ROUND(AVG(p.price_1m::numeric), 2) AS "Стоимость 1 кв.м.",
	ROUND(AVG(f.total_area::numeric), 2) AS "Общая площадь",
	ROUND(AVG(a.days_exposition::numeric), 0) AS "Срок экспозиции"
FROM real_estate.flats AS f
JOIN real_estate.advertisement AS a ON a.id = f.id
JOIN price_1m2 AS p ON p.p1m_id = f.id
LEFT JOIN real_estate.city AS ct ON ct.city_id = f.city_id
WHERE 
	p.price_1m < (SELECT price_1m_limit_h FROM limits)
	AND p.price_1m > (SELECT price_1m_limit_l FROM limits)
	AND (f.rooms < (SELECT rooms_limit FROM limits) OR f.rooms IS NULL)
	AND (f.balcony < (SELECT balcony_limit FROM limits) OR f.balcony IS NULL)
	AND ((f.ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
	AND f.ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR f.ceiling_height IS NULL)
	AND ct.city != 'Санкт-Петербург'
GROUP BY ct.city
ORDER BY "Количество объявлений" DESC
LIMIT 15;