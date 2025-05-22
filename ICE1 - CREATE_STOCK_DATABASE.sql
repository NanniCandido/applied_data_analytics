-- DBAS3090 - Applied Data Analytics
-- Elaine da Silva
-- DDL Stocks Data API Database
-- Scripts to create the Stocks Database
-- The database will be used to store and track data from Stocks
-- It will be updated daily using an automated script to gather the data from the API
-- API tidyquant / Yahoo Finance (yfinance)
-- table creation order: stock_sector, stock, stock_features, model_metrics
use master;
GO
-------------------------------------------------------------------------------------
-- CREATING THE STOCK DATABASE
-------------------------------------------------------------------------------------
IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = 'stocks')
BEGIN
  CREATE DATABASE stocks;
END;
GO

USE stocks;
GO

-------------------------------------------------------------------------------------
-- CREATING TABLES WITH ITS PRIMARY KEYS IN THE STOCK DATABASE
-------------------------------------------------------------------------------------
IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='stock_sector' AND xtype='U')
BEGIN
CREATE TABLE [dbo].[stock_sector](
	[ss_id] [int] IDENTITY(1,1) NOT NULL,
	[ss_name] [varchar](50) NOT NULL,
    CONSTRAINT PK_stock_sector PRIMARY KEY CLUSTERED (ss_id));
END;
GO

IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='stock' AND xtype='U')
BEGIN
	CREATE TABLE [dbo].[stock](
		[st_id] [int] IDENTITY(1,1) NOT NULL,
		[st_ticker] [varchar](10) NOT NULL,
		[st_date] [date] NOT NULL,
		[st_open_price] [float] NOT NULL,
		[st_high_price] [float] NOT NULL,
		[st_low_price] [float] NOT NULL,
		[st_close_price] [float] NOT NULL,
		[st_close_price_pred] [float] NULL,
		[st_volume] [bigint] NOT NULL,
		[st_adjusted_price] [float] NOT NULL,
		[ss_id_fk] [int] NULL
		CONSTRAINT PK_stock PRIMARY KEY CLUSTERED (st_id));
END;	
GO

IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='stock_features' AND xtype='U')
BEGIN
	CREATE TABLE [dbo].[stock_features](
		[sf_id] [int] IDENTITY(1,1) NOT NULL,
		[sf_ticker] [varchar](10) NOT NULL,
		[sf_date] [date] NOT NULL,
		[sf_close_price] [float] NOT NULL,
		[sf_daily_pct_change] [float] NULL,
		[sf_moving_avg_7d] [float] NULL,
		[sf_moving_avg_30d] [float] NULL,
		[sf_moving_avg_90d] [float] NULL,
		[sf_moving_avg_180d] [float] NULL,
		[sf_volatility_avg_7d] [float] NULL,
		[sf_volatility_avg_30d] [float] NULL,
		[sf_volatility_avg_90d] [float] NULL,
		[sf_volatility_avg_180d] [float] NULL
		CONSTRAINT PK_stock_features PRIMARY KEY CLUSTERED (sf_id));
END;	
GO

IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='model_metrics' AND xtype='U')
BEGIN
CREATE TABLE [dbo].[model_metrics](
	[mm_id] [int] IDENTITY(1,1) NOT NULL,
	[mm_name] [varchar](20) NOT NULL,
	[mm_date] [date] NOT NULL,
	[mm_rmse] [float] NULL,
	[mm_r2] [float] NULL,
	[mm_mae] [float] NULL	
    CONSTRAINT PK_model_metrics PRIMARY KEY CLUSTERED (mm_id));
END;
GO
-------------------------------------------------------------------------------------
-- CREATING UNIQUE INDEX
-- Doesn't allow duplicate date for the same stock
-------------------------------------------------------------------------------------

CREATE UNIQUE INDEX UIDX_stock
ON stock (st_ticker, st_date); 

-------------------------------------------------------------------------------------
-- CREATING FK CONSTRAINTS
-------------------------------------------------------------------------------------		

IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='FK_stock_ss_id' AND xtype='F')	
BEGIN
	ALTER TABLE [dbo].[stock]  
	ADD CONSTRAINT [FK_stock_ss_id] FOREIGN KEY([ss_id_fk])
	REFERENCES [dbo].[stock_sector] ([ss_id])
	ON UPDATE CASCADE
	ON DELETE CASCADE
END;
GO

-------------------------------------------------------------------------------------
-- TRIGGER TO UPDATE THE STOCK.SS_SS_ID_FK BASED ON TICKER
-------------------------------------------------------------------------------------	
-- =============================================
-- Author:		Elaine da Silva
-- Create date: 2025-03-22
-- Description:	Update the field sector_id on insert
-- =============================================
CREATE OR ALTER   TRIGGER [dbo].[trg_insert_sector_id]
   ON  [dbo].[stock] 
   AFTER INSERT AS 
BEGIN
	SET NOCOUNT ON;
	UPDATE stock set stock.ss_id_fk = CASE 
			when stock.st_ticker = 'META' then 5
			when stock.st_ticker = 'GOOGL' then 5
			when stock.st_ticker = 'MSFT' then 1
			when stock.st_ticker = 'AAPL' then 1
			when stock.st_ticker = 'NVDA' then 1
			when stock.st_ticker = 'AMZN' then 6
			when stock.st_ticker = 'TSLA' then 6 
			when stock.st_ticker = '^GSPC' then 7
			when stock.st_ticker = '^NDX' then 8
			when stock.st_ticker = 'UUP' then 9 END
	FROM INSERTED
	WHERE stock.ss_id_fk is null
END
GO

ALTER TABLE [dbo].[stock] ENABLE TRIGGER [trg_insert_sector_id]
GO

-------------------------------------------------------------------------------------
-- VIEW TO CREATE OTHERS FIELDS BASED ON THE DATE
-- iT WILL BE TAKEN TO POWER BI ALREADY DONE
-------------------------------------------------------------------------------------	
CREATE OR ALTER VIEW vw_stock AS
SELECT 	  st_date
		, st_ticker
		, st_open_price
		, st_high_price
		, st_low_price
		, st_close_price
		, st_close_price_pred
		, st_adjusted_price
        , st_volume		
		, ss_name ss_sector_name
		, DATEPART(year, st_date) st_year 
		, DATEPART(month, st_date) st_month
		, DATEPART(quarter, st_date) st_quarter
		, DATEPART(day, st_date) st_dayofmonth
		, DATEPART(dayofyear, st_date) st_dayofyear 
		, DATEPART(weekday, st_date) st_weekday
		, case DATEPART(weekday, st_date)
		  when 1 then 'Sunday'
		  when 2 then 'Monday'
		  when 3 then 'Tuesday'
		  when 4 then 'Wednesday'
		  when 5 then 'Thursday'
		  when 6 then 'Friday'
		  else 'Saturday' end st_name_day
		 , case DATEPART(month, st_date)
		  when 1 then 'January'
		  when 2 then 'February'
		  when 3 then 'March'
		  when 4 then 'April'
		  when 5 then 'May'
		  when 6 then 'June'
		  when 7 then 'July'
		  when 8 then 'August'
		  when 9 then 'September'
		  when 10 then 'October'
		  when 11 then 'November'
		  else 'December' end st_name_month,
		  ROUND(
            (st_close_price / NULLIF(LAG(st_close_price) OVER (PARTITION BY st_ticker ORDER BY st_date), 0) * 100) - 100, 
            2
          ) AS st_profit,
		  CASE WHEN st_close_price > LAG(st_close_price) OVER (PARTITION BY st_ticker ORDER BY st_date) 
		  THEN 'Up'
		  ELSE 'Down' 
		  END AS st_trend
FROM stock s inner join stock_sector ss on s.ss_id_fk = ss.ss_id

-------------------------------------------------------------------------------------
-- script to update the known Y (st_close_price_pred)
-------------------------------------------------------------------------------------	
--with update_y as 
--(
--     SELECT st_date, st_ticker, st_close_price, 
--            LEAD(st_close_price, 1) OVER(PARTITION BY st_ticker ORDER BY st_date) as y
--       FROM stock
--)
--update s set s.st_close_price_pred = u.y
--  from stock s inner join update_y u 
--    on s.st_ticker = u.st_ticker and s.st_date = u.st_date
--  where st_close_price_pred is null
  
-------------------------------------------------------------------------------------
-- EXAMPLES OF WORKING WITH DATE
-------------------------------------------------------------------------------------	

--SELECT DATEPART(year, getdate()) ano 
--      ,DATEPART(month, getdate()) mes
--      ,DATEPART(quarter, getdate()) quartil
--      ,DATEPART(day, getdate()) dia
--      ,DATEPART(dayofyear, getdate()) "dia no ano" 
--      ,DATEPART(weekday, getdate()) "dia da semana";  

--SELECT DATENAME(year, getdate()) ano 
--    ,DATENAME(quarter, getdate()) quartil
--	  ,DATENAME(month, getdate()) mes
--    ,DATENAME(day, getdate()) dia
--    ,DATENAME(dayofyear, getdate()) "dia no ano"
--    ,DATENAME(weekday, getdate()) "dia da semana";  
	

  