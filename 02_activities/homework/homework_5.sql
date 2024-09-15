-- Cross Join
/*1. Suppose every vendor in the `vendor_inventory` table had 5 of each of their products to sell to **every** 
customer on record. How much money would each vendor make per product? 
Show this by vendor_name and product name, rather than using the IDs.

HINT: Be sure you select only relevant columns and rows. 
Remember, CROSS JOIN will explode your table rows, so CROSS JOIN should likely be a subquery. 
Think a bit about the row counts: how many distinct vendors, product names are there (x)?
How many customers are there (y). 
Before your final group by you should have the product of those two queries (x*y).  */


WITH
	-- Retrieve the highest price for each product offered by each vendor
	_price_list AS (
	SELECT 
		vi.vendor_id,
		v.vendor_name,
		vi.product_id, 
		-- Use the highest price in case there are more than one:
		max(vi.original_price) AS price
	FROM vendor_inventory vi
	INNER JOIN vendor v
		ON vi.vendor_id = v.vendor_id
	GROUP BY vi.vendor_id, v.vendor_name, vi.product_id
)
-- Cross join each product with all customers, and compute total sale per each
-- combination assuming each customer buys 5 units
SELECT
	pl.vendor_name, 
	p_x_c.product_name,
	sum(pl.price * 5.0) as total_sell  
FROM _price_list pl
JOIN (
	SELECT product_id, product_name
	FROM product p
	CROSS JOIN customer c
) p_x_c
	ON pl.product_id = p_x_c.product_id
GROUP BY pl.vendor_name, p_x_c.product_name;


-- INSERT
/*1.  Create a new table "product_units". 
This table will contain only products where the `product_qty_type = 'unit'`. 
It should use all of the columns from the product table, as well as a new column for the `CURRENT_TIMESTAMP`.  
Name the timestamp column `snapshot_timestamp`. */

-- Optionally delete the table if it already exists, to make it easier to
-- re-run this SQL script:
-- DROP TABLE IF EXISTS product_units;

-- Create a new table product_units containing products sold by unit, and add a
-- snapshot timestamp
CREATE TABLE product_units AS
	SELECT *, CURRENT_TIMESTAMP AS snapshot_timestamp
	FROM product
	WHERE product_qty_type = 'unit';

/*2. Using `INSERT`, add a new row to the product_units table (with an updated timestamp). 
This can be any product you desire (e.g. add another record for Apple Pie). */

-- Duplicate the Apple Pie product row with an updated timestamp
INSERT INTO product_units
SELECT 
	product_id,
	product_name, 
	product_size, 
	product_category_id, 
	product_qty_type, 
	CURRENT_TIMESTAMP as snapshot_timestamp
FROM product_units s
WHERE s.product_name = 'Apple Pie'
LIMIT 1;

-- DELETE
/* 1. Delete the older record for the whatever product you added. 

HINT: If you don't specify a WHERE clause, you are going to have a bad time.*/

-- Delete the oldest entry of the Apple Pie product based on the timestamp
DELETE FROM product_units 
WHERE (product_id, snapshot_timestamp) = (
	SELECT x.product_id, min(x.snapshot_timestamp) -- Oldest
	FROM product_units x
	WHERE x.product_name = 'Apple Pie'
	GROUP BY x.product_id
);

-- UPDATE
/* 1.We want to add the current_quantity to the product_units table. 
First, add a new column, current_quantity to the table using the following syntax.*/

-- Add a current_quantity column to store the latest quantity from vendor
-- inventory
ALTER TABLE product_units
ADD current_quantity INT;

/* Then, using UPDATE, change the current_quantity equal to the last quantity value from the vendor_inventory details.

HINT: This one is pretty hard. 
First, determine how to get the "last" quantity per product. 
Second, coalesce null values to 0 (if you don't have null values, figure out how to rearrange your query so you do.) 
Third, SET current_quantity = (...your select statement...), remembering that WHERE can only accommodate one column. 
Finally, make sure you have a WHERE statement to update the right row, 
	you'll need to use product_units.product_id to refer to the correct row within the product_units table. 
When you have all of these components, you can run the update statement. */

WITH
	-- Retrieve the latest quantity per product, using the most recent
	-- market date
	_last_quantity_per_product AS (
		SELECT * FROM (
			-- Using a 'sum' and 'group by' is not strictly necessary for the data we have,
			-- but it would be if we had more than one vendor offering the same product on 
			-- the same day. So let's assume the more general case.
			SELECT 
				product_id,
				sum (quantity) AS quantity_per_product, 
				row_number() OVER (PARTITION BY product_id ORDER BY market_date DESC) as rn
			FROM vendor_inventory
			GROUP BY product_id, market_date
		) 
		WHERE rn = 1
	),
	-- Ensure all products from product table are included, assigning 0 if
	-- no vendor inventory is available
	_quantity_update AS (
		SELECT p.product_id, coalesce(quantity_per_product, 0.0) as quantity
		FROM _last_quantity_per_product lqp
		RIGHT JOIN product p
			ON lqp.product_id = p.product_id
	)
-- Update the current_quantity in product_units with the latest quantity from
-- vendor inventory (or zero, if it's not in any vendor inventory)
UPDATE product_units
SET 
	current_quantity = s.quantity
	-- ,snapshot_timestamp = CURRENT_TIMESTAMP -- Should we update the timestamp?
FROM
	_quantity_update s
WHERE
	product_units.product_id = s.product_id;
