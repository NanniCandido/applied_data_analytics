#=================================================================
# Author: Elaine da Silva
# Date: Feb 2025
# Purpose: Get data from API and insert it directly into the STOCK table 
#
# set the encoding to be used for the SQL Server jobs in order to generate an output file 
# with portuguese accentuation
#
Sys.setlocale("LC_ALL", "pt_BR.UTF-8")  # Set Portuguese (Brazil) locale
Sys.setlocale("LC_CTYPE", "Portuguese_Brazil.1252") # For Windows
options(encoding = "UTF-8")             # Ensure UTF-8 encoding for text output

# Set the work directory
setwd("C:/Users/elain/OneDrive/Documents/NSCC/Term_4/DBAS3090 - Applied Data Analytics/repo/Project/")

# Adjust the library path to be used by SQL Server Agent
.libPaths(c("C:/Users/elain/AppData/Local/R/win-library/4.4",  
            "C:/Program Files/R/R-4.4.1/library"))

# Set the libraries
library(tidyquant)
library(tidyverse)
library(DBI)
library(odbc)

# Create the dataframe with the tickers needed
stocks = c("AAPL", "AMZN", "GOOGL", "META", "MSFT", "NVDA", "TSLA", "^NDX", "^GSPC", "UUP")

# Get stock prices for yesterday
tickers <- tq_get(stocks,
                  get  = "stock.prices",
                  from = Sys.Date() - 1,
                  to   = Sys.Date())

# Rename columns to match SQL Server table structure
tickers <- tickers %>%
  rename(
    st_ticker = symbol,
    st_date = date,
    st_open_price = open,
    st_high_price = high,
    st_low_price = low,
    st_close_price = close,
    st_adjusted_price = adjusted,
    st_volume = volume
  ) 

# Connect to SQL Server
con <- dbConnect(odbc::odbc(),
                 Driver = "ODBC Driver 17 for SQL Server",
                 Server = "4FTGXM3\\SQLEXPRESS",
                 Database = "stocks",
                 Trusted_Connection = "Yes")  

# Insert data into SQL Server
dbWriteTable(con, "stock", tickers, append = TRUE, row.names = FALSE)

# Close the connection
dbDisconnect(con)
