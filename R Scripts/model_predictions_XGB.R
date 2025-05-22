#=================================================================
# Author: Elaine da Silva
# Date: Mar 2025
# Purpose: Get data from STOCKS database to create a XGBoost prediction model
#
#Sys.setlocale("LC_ALL", "pt_BR.UTF-8")  # Set Portuguese (Brazil) locale
Sys.setlocale("LC_CTYPE", "Portuguese_Brazil.1252") # For Windows
options(encoding = "UTF-8")             # Ensure UTF-8 encoding for text output

# Set the work directory
setwd("C:/Users/elain/OneDrive/Documents/NSCC/Term_4/DBAS3090 - Applied Data Analytics/repo/Project/")

# Adjust the library path to be used by SQL Server Agent
.libPaths(c("C:/Users/elain/AppData/Local/R/win-library/4.4",  
            "C:/Program Files/R/R-4.4.1/library"))

# Set the libraries
library(xgboost)
library(caret)
library(DBI)
library(odbc)
library(dplyr)
library(ggplot2)

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
query = "WITH y_tmp AS (
SELECT st_ticker, st_date, 
       LEAD(st_close_price, 1) OVER(PARTITION BY st_ticker ORDER BY st_date) st_close_price_pred  
  FROM stock )
SELECT s.st_ticker, s.st_date, s.st_open_price, 
       s.st_high_price, s.st_low_price, s.st_close_price, 
	     y.st_close_price_pred, s.st_adjusted_price, s.st_volume
  FROM stock s INNER JOIN y_tmp y 
    ON s.st_ticker = y.st_ticker and s.st_date = y.st_date
 WHERE y.st_close_price_pred IS NOT NULL "

# Load data from SQL Server
stock = dbGetQuery(con, query)

# ===== PART 2: Prepare the data ======================================================
# =====================================================================================
# Changing the categorical columns to factor types
# Convert categorical columns
#
stock <- stock %>% mutate(st_ticker = as.factor(st_ticker)) 

# split train and test data
#
set.seed(62)
trainIndex <- createDataPartition(stock$st_close_price, p = 0.8, list = FALSE) # 80% train, 20% test
trainData <- stock[trainIndex, ]
testData  <- stock[-trainIndex, ]

#str(stock)

# train data
train_x = model.matrix(~ . - 1, trainData[, -6])
train_y = trainData[, 6]
# test data
test_x = model.matrix(~ . - 1, testData[, -6])
test_y = testData[, 6]

#===== PART 3: Train the models ======================================================
#=====================================================================================
## Model 4: XGBoost ==> create a XGBoostn model, trained with the training data set
# train the model using XGBoost library
# 
xgb_train = xgb.DMatrix(data = train_x, label = train_y)
xgb_test = xgb.DMatrix(data = test_x, label = test_y)
watchlist = list(train=xgb_train, test=xgb_test)

model_xgb <- xgb.train(data = xgb_train, max.depth = 2, 
                       watchlist=watchlist, 
                       nrounds = 10000,
                       objective = "reg:squarederror",  # For continuos target
                       eval_metric = "rmse"  )

#===== PARTE 4: Make the predictions =================================================
#=====================================================================================
# XGBoost
# make the predictions - XGBoost model using the testData
#  
predict_xgb <- predict(model_xgb, xgb_test)

# evaluate the model (RMSE, Rsquared, MAE)
evaluate_xgb <- postResample(predict_xgb, test_y)

predict_xgb <- data.frame(st_ticker = testData$st_ticker, 
                          st_date = testData$st_date,
                          st_close_price = testData$st_close_price,
                          st_close_price_pred = predict_xgb)

# get the metrics values to store in database (RMSE, R2, and MAE)
metrics_xgb <- data.frame(mm_name = 'XGBoost',
                          mm_date = Sys.Date(),
                          mm_rmse = evaluate_xgb["RMSE"],
                          mm_r2 = evaluate_xgb["Rsquared"],
                          mm_mae = evaluate_xgb["MAE"])

# Insert the metrics data into SQL Server
dbWriteTable(con, "model_metrics", metrics_xgb, append = TRUE, row.names = FALSE)


# Close the connection
dbDisconnect(con)

#===== PARTE 5: Evaluate the metrics =================================================
#=====================================================================================
# OUTPUTS
#
head(predict_xgb)

# Verify RMSE, Rsquared, MAE
print(evaluate_xgb)

#===== PARTE 6: Save the model to disk ===============================================
#=====================================================================================
# save the model to disk to reuse with new data later
#
saveRDS(model_xgb, "./outputs/final_model_xgb.rds")
#xgb.save(model_xgb, "./outputs/final_model_xgb.bin")

#===== PARTE 7: SAVE DATAFRAMES ======================================================	
##====================================================================================
#
# get the the model variables importance
importance <- xgb.importance(feature_names = colnames(xgb_train), model = model_xgb)

#xgb.plot.importance(importance_matrix = importance)

# Convert importance output into a data frame
importance_xgb <- importance %>%
  select(Feature, Gain) %>%
  arrange(desc(Gain))  # Order from biggest to lowest

# Show variables
print(importance_xgb)
str(importance)

# Save Importance, metrics, and predictions to a csv file
# for importing it into the Power BI
#
write.csv(importance_xgb, "./outputs/importance_xgb.csv", row.names = FALSE)
write.csv(predict_xgb, "./outputs/predict_xgb.csv", row.names = FALSE)
write.csv(metrics_xgb, "./outputs/metrics_xgb.csv", row.names = FALSE)
##====================================================================================

#===== PARTE 8: CHARTS ===============================================================
# ====================================================================================
# Chart below shows the importance of each variable to built the model XGBoost
# ====================================================================================
# # Plot the importance of each variable
# ggplot(importance_xgb, aes(x = reorder(Feature, Gain), y = Gain)) +
#   geom_bar(stat = "identity", fill = "steelblue") +
#   coord_flip() +  # Flip for better readability
#   labs(
#     title = "Variable Importance (XGBoost)",
#     x = "Variables", 
#     y = "Gain"
#   ) +
#   theme_minimal() + 
#   theme(
#     axis.text.x = element_text(angle = 45, hjust = 1),  # Rotate X-axis labels
#     plot.title = element_text(hjust = 0.5, size = 14, face = "bold"),  # Center title
#     plot.subtitle = element_text(hjust = 0.5, size = 12, face = "italic"),  # Center subtitle
#     plot.caption = element_text(hjust = 0, face = "italic")  # Left-align caption
#   )
# ggsave("./outputs/variable_importance_xgb.png", width = 10, height = 5, dpi = 300)			
# #===========================================================================================
# # Plot 
# # XGBoost
# diff_xgb <- predict_xgb$st_close_price_pred - predict_xgb$st_close_price
# plot(diff_xgb,  
#      main = "Difference between actual and predicted", 
#      col = ifelse(diff_xgb >= 0, "blue", "red"),  # Azul para diferença positiva, vermelho para negativa
#      pch = 16)  # Pontos sólidos
# abline(h = 0, col = "black", lty = 2)  # Linha horizontal em zero
# 
# #===========================================================================================
# # Plot REAL vs Predict with Events
# #
# events <- data.frame(
#   event_date = as.Date(c("2022-11-15", "2024-07-15", "2024-11-05", "2025-01-20", "2025-03-10")),  # Events dates
#   event_name = c("Announced", "Official Nomination", "Election Day", "Inauguration", "Trade War effect")  # Events names
# )
# 
# # Chart for XGBoost (DIFFERENT COLOR FOR EACH STOCK)
# predict_xgb <- predict_xgb %>% filter(st_ticker %in% c("AMZN", "GOOGL", "META", "TSLA"))
# 
# ggplot(predict_xgb, aes(x = st_date, group = st_ticker)) +
#   # Real Prices: Unique color for each stock
#   geom_line(aes(y = st_close_price, color = st_ticker), linewidth = 1) +  
#   # Prediction: Always black
#   geom_line(aes(y = st_close_price_pred), color = "black", linewidth = 1, linetype = "dashed") +  
#   # Prevent event lines from inheriting aesthetics
#   geom_vline(data = events, aes(xintercept = event_date), linetype = "dashed", color = "black", linewidth = 1) +
#   # Prevent event labels from inheriting aesthetics
#   geom_text(data = events, aes(x = event_date, y = max(predict_xgb$st_close_price) * 1.05, label = event_name), 
#             angle = 90, vjust = 1.5, hjust = 1, color = "black", size = 4, inherit.aes = FALSE) +
#   labs(
#     title = "Real vs Prediction - XGBoost",
#     subtitle = "Stock price trends and predictions",
#     y = "Closing Price",
#     x = "Date",
#     color = "Ticker",
#     caption = "Data source: tidyquant | Predictions based on XGBoost model" ) +
#   # Use ggplot's automatic color palette for different stocks
#   scale_color_manual(values = scales::hue_pal()(length(unique(predict_xgb$st_ticker)))) +
#   scale_x_date(labels = scales::date_format("%Y-%m"), breaks = scales::date_breaks("3 months")) +
#   theme_minimal() + 
#   theme(
#     axis.text.x = element_text(angle = 45, hjust = 1),  # Rotate X-axis labels
#     plot.title = element_text(hjust = 0.5, size = 14, face = "bold"),  # Center title
#     plot.subtitle = element_text(hjust = 0.5, size = 12, face = "italic"),  # Center subtitle
#     plot.caption = element_text(hjust = 0, face = "italic")  # Left-align caption
#   )
# ggsave("./outputs/stock_predict_xgb.png", width = 9, height = 5, dpi = 150)
# 
# #===========================================================================================
# # Plot REAL vs Predict with Events
# # create a vector with the tickets
# tickers <- c("AMZN", "GOOGL", "META", "TSLA")
# 
# for (ticker in tickers) { 
#   
#   filtered_data <- predict_xgb %>% filter(st_ticker == ticker) 
#   
#   # Chart for XGBoost (RED/BLUE)
#   stock_plot <- ggplot(filtered_data, aes(x = st_date, group = st_ticker, color = st_ticker)) +
#     geom_line(aes(y = st_close_price, color = "Real", linetype = st_ticker), size = 1) +
#     geom_line(aes(y = st_close_price_pred, color = "Prediction", linetype = st_ticker), size = 1) +
#     # Adding vertical event lines
#     geom_vline(data = events, aes(xintercept = event_date), linetype = "dashed", color = "black", size = 1) +
#     # Adding labels to the events
#     geom_text(data = events, aes(x = event_date, y = max(filtered_data$st_close_price) * 1.05, label = event_name), 
#               angle = 90, vjust = 1.0, hjust = 1, color = "black", size = 4, inherit.aes = FALSE) +
#     labs(
#       title = "Real vs Prediction - XGBoost",
#       subtitle = "Stock price trends and predictions",
#       y = "Closing Price",
#       x = "Date",
#       color = "Ticker",
#       caption = "Data source: tidyquant | Predictions based on XGBoost model" ) +
#     # Define custom colors
#     scale_color_manual(values = c("Real" = "blue", "Prediction" = "red")) +
#     # Adjust the date scale on X axis
#     scale_x_date(labels = scales::date_format("%Y-%m"), breaks = scales::date_breaks("3 months")) +
#     theme_minimal() + 
#     theme(
#       axis.text.x = element_text(angle = 45, hjust = 1),  # Rotate X-axis labels
#       plot.title = element_text(hjust = 0.5, size = 14, face = "bold"),  # Center title
#       plot.subtitle = element_text(hjust = 0.5, size = 12, face = "italic"),  # Center subtitle
#       plot.caption = element_text(hjust = 0, face = "italic")  # Left-align caption
#     )
#   ggsave(paste0("./outputs/stock_predict_xgb_", ticker, ".png"), width = 9, height = 5, dpi = 150)
# }
#  