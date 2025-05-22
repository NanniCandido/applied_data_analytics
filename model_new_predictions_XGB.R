#=================================================================
# Author: Elaine da Silva
# Date: Mar 2025
# Purpose: Reuse the XGBoost model previously created
#
# Set the encoding when executed from SQL Server
Sys.setlocale("LC_CTYPE", "Portuguese_Brazil.1252") # For Windows
options(encoding = "UTF-8")             # Ensure UTF-8 encoding for text output

# Set the work directory
setwd("C:/Users/elain/OneDrive/Documents/NSCC/Term_4/DBAS3090 - Applied Data Analytics/repo/Project/")

# Adjust the library path to be used by SQL Server Agent
.libPaths(c("C:/Users/elain/AppData/Local/R/win-library/4.4",  
            "C:/Program Files/R/R-4.4.1/library"))

# Set the libraries
library(DBI)
library(odbc)
library(dplyr)
library(ggplot2)
library(xgboost)
library(caret)

# ===== PART 1: Connect to SQL Server =================================================
# =====================================================================================
# Connect to SQL Server
#
con <- dbConnect(odbc::odbc(),
                 Driver = "ODBC Driver 17 for SQL Server",
                 Server = "4FTGXM3\\SQLEXPRESS",
                 Database = "stocks",
                 Trusted_Connection = "Yes")  

# create a query
query_stocks = "WITH y_tmp AS (
SELECT st_ticker, st_date, 
       LEAD(st_close_price, 1) OVER(PARTITION BY st_ticker ORDER BY st_date) st_close_price_pred  
  FROM stock )
SELECT s.st_ticker, s.st_date, s.st_open_price, 
       s.st_high_price, s.st_low_price, s.st_close_price, 
       y.st_close_price_pred, s.st_adjusted_price, s.st_volume
  FROM stock s INNER JOIN y_tmp y 
    ON s.st_ticker = y.st_ticker and s.st_date = y.st_date
 WHERE y.st_close_price_pred IS NULL"

query_metrics = "SELECT mm_date, mm_name, mm_rmse, mm_r2, mm_mae 
                   FROM model_metrics 
                  WHERE mm_id =  (SELECT max(mm_id) FROM model_metrics)
                    AND mm_name = 'XGBoost'"

# Load data from SQL Server
stock_prices = dbGetQuery(con, query_stocks)
model_metrics = dbGetQuery(con, query_metrics)

# ===== PART 2: LOAD THE MODEL FROM DISK ==============================================
# =====================================================================================
# Changing the categorical columns to factor types
# Convert categorical columns
#
# load the model
model_xgb <- readRDS("C:/Users/elain/OneDrive/Documents/NSCC/Term_4/DBAS3090 - Applied Data Analytics/repo/Project/outputs/final_model_xgb.rds")
print(model_xgb)
#xgb_model <- xgb.load("C:/Users/elain/OneDrive/Documents/NSCC/Term_4/DBAS3090 - Applied Data Analytics/repo/Project/outputs/final_model_xgb.bin")
#print(xgb_model)

# ===== PART 3: PREPARE THE NEW DATA ==================================================
# =====================================================================================
# Changing the categorical columns to factor types
# Convert categorical columns
#
stock_prices <- stock_prices %>% mutate(st_ticker = as.factor(st_ticker),
                                        st_close_price_pred = st_close_price)

# convert the new data into a matrix
new_stock_x <- model.matrix(~ . - 1, stock_prices[, -6])  # transform the variables to numeric
new_stock_y <- stock_prices[, 6]
xgb_new_stock <- xgb.DMatrix(data = new_stock_x, label=new_stock_y)

# verify number of rows
#nrow(new_stock_x)
#nrow(new_stock_y)
#print(xgb_new_stock)

# ===== PART 4: MAKE NEW PREDICTIONS ==================================================
# =====================================================================================
#
# Predict new data using the trained XGBoost model
predict_xgb <- predict(model_xgb, newdata = xgb_new_stock)
#predict_xgb2 <- predict(xgb_model, newdata = xgb_new_stock)

# ===== PART 5: EVALUATE THE MODEL ====================================================
# =====================================================================================
#
# evaluate the model (RMSE, Rsquared, MAE)
evaluate_xgb <- postResample(predict_xgb, stock_prices$st_close_price)
#evaluate_xgb2 <- postResample(predict_xgb2, stock_prices$st_close_price)

print(evaluate_xgb)
#print(evaluate_xgb2)

# ===== PART 6: SAVE DATA INTO DATABASE ===============================================
# =====================================================================================
#
# get the metrics values to store in database
new_metrics_xgb <- data.frame(mm_name = 'XGBoost',
                              mm_date = Sys.Date(),
                              mm_rmse = evaluate_xgb["RMSE"],
                              mm_r2 = evaluate_xgb["Rsquared"],
                              mm_mae = evaluate_xgb["MAE"])

# Insert the metrics data into SQL Server
dbWriteTable(con, "model_metrics", new_metrics_xgb, append = TRUE, row.names = FALSE)

new_predict_xgb <- data.frame(st_ticker = stock_prices$st_ticker,
                              st_date = stock_prices$st_date,
                              st_close_price = stock_prices$st_close_price,
                              st_close_price_pred = predict_xgb)

# create the prediction dataframe to save the predictions in database
for (i in 1:nrow(new_predict_xgb)) {
  query <- sprintf(
    "UPDATE stock SET st_close_price_pred = %f 
      WHERE st_ticker = '%s' and st_date = '%s' and st_close_price_pred is null",
    new_predict_xgb$st_close_price_pred[i],
    new_predict_xgb$st_ticker[i],
    format(new_predict_xgb$st_date[i], '%Y-%m-%d')
  )
  dbExecute(con, query)
}

# Close the connection
dbDisconnect(con)

# ===== PART 7: SAVE MODEL TO DISK (conditional)=======================================
# Before saving, verify if the model performed better or worst than the previous one
# =====================================================================================
#
# Verify if this model is better than the previous one
if (evaluate_xgb["RMSE"] < model_metrics$mm_rmse && 
    evaluate_xgb["Rsquared"] > model_metrics$mm_r2 && 
    evaluate_xgb["MAE"] < model_metrics$mm_mae) {
  
  print('===>>> New Model is better than the old one!')
  # model had better performance than previous
  # save the model to disk to reuse with new data later
  saveRDS(model_xgb, "C:/Users/elain/OneDrive/Documents/NSCC/Term_4/DBAS3090 - Applied Data Analytics/repo/Project/outputs/final_model_xgb.rds")
  
} else {
  print('===>>> New Model is worst than the old one!')
}

# ===== PART 8: SAVE NEW PREDICTIONS AND METRICS TO CSV ===============================
# =====================================================================================
# Save Importance, metrics, and predictions to a csv file
# for importing it into the Power BI, if needed
#
#write.csv(importance_xgb, "C:/Users/elain/OneDrive/Documents/NSCC/Term_4/DBAS3090 - Applied Data Analytics/repo/Project/outputs/importance_xgb.csv", row.names = FALSE)
write.csv(new_predict_xgb, "C:/Users/elain/OneDrive/Documents/NSCC/Term_4/DBAS3090 - Applied Data Analytics/repo/Project/outputs/new_predict_xgb.csv", row.names = FALSE)
write.csv(new_metrics_xgb, "C:/Users/elain/OneDrive/Documents/NSCC/Term_4/DBAS3090 - Applied Data Analytics/repo/Project/outputs/new_metrics_xgb.csv", row.names = FALSE)
##============================================================================

