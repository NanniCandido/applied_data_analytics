#=================================================================
# Author: Elaine da Silva
# Date: Mar 2025
# Purpose: Calculate the STOCKS moving_average and volability and 
#          insert it into the STOCK_FEATURES table
#
# set the encoding to be used for the SQL Server jobs in order to generate an output file with portuguese accentuation
Sys.setlocale("LC_CTYPE", "Portuguese_Brazil.1252") # For Windows
options(encoding = "UTF-8")             # Ensure UTF-8 encoding for text output

# Set the work directory
setwd("C:/Users/elain/OneDrive/Documents/NSCC/Term_4/DBAS3090 - Applied Data Analytics/repo/Project/")

# Adjust the library path to be used by SQL Server Agent
.libPaths(c("C:/Users/elain/AppData/Local/R/win-library/4.4",  
            "C:/Program Files/R/R-4.4.1/library"))

# Set the libraries
#library(stats)
library(zoo)
library(DBI)
library(odbc)
library(dplyr)
library(tidyr)
library(ggplot2)

# Connect to SQL Server
con <- dbConnect(odbc::odbc(),
                 Driver = "ODBC Driver 17 for SQL Server",
                 Server = "4FTGXM3\\SQLEXPRESS",
                 Database = "stocks",
                 Trusted_Connection = "Yes")  

# Load data from SQL Server
data = dbGetQuery(con, "select st_date, st_ticker, st_close_price 
                          from stock")

# TRUNCATE the table first (removes all rows but keeps structure and identity)
dbExecute(con, "TRUNCATE TABLE stock_features")

tickers <- c('AAPL', 'AMZN', 'GOOGL', 'META', 'MSFT', 'NVDA', 'TSLA', '^GSPC', '^NDX', 'UUP')

for (ticker in tickers) { 
  
  filtered_data <- data %>% filter(st_ticker == ticker) 
  
# Group by ticker and calculate moving averages and volatility
metrics <- filtered_data %>%
  group_by(st_ticker) %>%
  arrange(st_date) %>%
  mutate(
    # Convert 'st_close_price' into a zoo object using st_date
    price_zoo = zoo(st_close_price, order.by = st_date),
    
    # Calculate moving averages using rollmean from zoo
    MA7 = rollmean(price_zoo, 7, fill = NA, align = "right"),
    MA30 = rollmean(price_zoo, 30, fill = NA, align = "right"),
    MA90 = rollmean(price_zoo, 90, fill = NA, align = "right"),
    MA180 = rollmean(price_zoo, 180, fill = NA, align = "right"),
    
    # Calculate the percentage of change between today and yesterday
    pct_change = (st_close_price - lag(st_close_price)) / lag(st_close_price),
    
    # Calculate volatility using rollapply from zoo (standard deviation of returns)
    vol7 = rollapply(pct_change, 7, sd, fill = NA, align = "right"),
    vol30 = rollapply(pct_change, 30, sd, fill = NA, align = "right"),
    vol90 = rollapply(pct_change, 90, sd, fill = NA, align = "right"),
    vol180 = rollapply(pct_change, 180, sd, fill = NA, align = "right")
  ) %>%
  ungroup() %>%
  select(-price_zoo)  # Remove the zoo object after calculation

# Rename columns to match SQL Server table structure
features <- metrics %>%
  rename(
    sf_ticker = st_ticker,
    sf_date = st_date, 
    sf_close_price = st_close_price,
    sf_daily_pct_change = pct_change,
    sf_moving_avg_7d = MA7,
    sf_moving_avg_30d = MA30,
    sf_moving_avg_90d = MA90,
    sf_moving_avg_180d = MA180,
    sf_volatility_avg_7d = vol7,
    sf_volatility_avg_30d = vol30,
    sf_volatility_avg_90d = vol90,
    sf_volatility_avg_180d = vol180
  ) 

# Insert data into SQL Server
dbWriteTable(con, "stock_features", features, append = TRUE, row.names = FALSE)
}

# Close the connection
dbDisconnect(con)

# Plot the Moving Averages
#plot_ma <- ggplot(metrics, aes(x = st_date)) +
#  geom_line(aes(y = as.numeric(MA7), color = "MA 7"), linewidth = 1) +
#  geom_line(aes(y = as.numeric(MA30), color = "MA 30"), linewidth = 1) +
#  geom_line(aes(y = as.numeric(MA90), color = "MA 90"), linewidth = 1) +
#  geom_line(aes(y = as.numeric(MA180), color = "MA 180"), linewidth = 1) +
#  labs(title = "Moving Averages", x = "Date", y = "Value") +
#  scale_color_manual(values = c("blue", "green", "red", "purple")) +
#  facet_wrap(~st_ticker)
#plot_ma

# Save the plot to the specified path
#ggsave("C:/Users/elain/OneDrive/Documents/NSCC/Term_4/DBAS3090 - Applied Data Analytics/repo/Project/ma_chart.png", 
#       plot = plot_ma, width = 9, height = 5, dpi = 150)

# Create the plot and store it in a variable
#plot_vol <- ggplot(metrics, aes(x = st_date)) +
#  geom_line(aes(y = as.numeric(vol7), color = "Vol 7"), linewidth = 1) +
#  geom_line(aes(y = as.numeric(vol30), color = "Vol 30"), linewidth = 1) +
#  geom_line(aes(y = as.numeric(vol90), color = "Vol 90"), linewidth = 1) +
#  geom_line(aes(y = as.numeric(vol180), color = "Vol 180"), linewidth = 1) +
#  labs(title = "Volatility", x = "Date", y = "Volatility") +
#  scale_color_manual(values = c("blue", "green", "red", "purple")) +
#  facet_wrap(~st_ticker)
#plot_vol
# Save the plot to the specified path
#ggsave("C:/Users/elain/OneDrive/Documents/NSCC/Term_4/DBAS3090 - Applied Data Analytics/repo/Project/vol_chart.png", 
#       plot = plot_vol, width = 9, height = 5, dpi = 1500)

