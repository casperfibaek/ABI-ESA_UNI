

# Random Forest Classification for School Indicator

## Set Up

### Packages

library(readr)
library(terra)
library(randomForest)
library(datasets)
library(caret)
library(sf)
library(dplyr)
library(ranger)  
library(kableExtra)
library(caret)
library(rmarkdown)


### Load in Data

'Africa grids 10km x 10km using GHSL grids and data

Set seed'

setwd("/home/azureuser/cloudfiles/code/Users/ariley/FINAL")
#setwd("C:/Users/air21/Documents/UNICEF-ESA/Code/FINAL")

grid_data <- read.csv("Data/Africa_Grid_Data_10km_ghsl.csv")

set.seed(23)


## Individual African Country Models

### Set-Up Data

'Load in data, remove any missing data, name the variables something slightly more sensible, specify countries, and create factor indicator for schools/no schools.'

data <- grid_data[,-1]
data <- na.omit(data)
head(data)
names(data)[c(9:16)] <- c("smod.10", "smod.11", "smod.12", "smod.13", "smod.21", "smod.22", "smod.23", "smod.30")

countries <- c("BEN", "BWA", "GHA", "GIN", "KEN", "MWI", "NAM", "NER", "NGA", "RWA", "SLE", "SSD", "ZAF", "ZWE")

data$SCHOOLS <- as.factor(ifelse(data$NUMPOINTS > 0, 1, 0))


## Fit Initial Random Forest Classification Models

'1. Subset individual country data
2. Sample testing and training set (training fraction = 0.7)
3. Run Random Forest model with formula
  $$
  SCHOOLS ~ x + y + land + pop +  built_s + built_v + smod.10 + smod.11 + smod.12 + smod.13 + smod.21 + smod.22 + smod.23 + smod.30
  $$
4. Save to file'


set.seed(23)

country.data <- list()
ind <- list()
train <- list()
test <- list()
rf <- list()
for (i in 1:14){ #1:length(countries)) {
  country.data[[i]] <- subset(data, country == i)
  ind[[i]] <- sample(2, nrow(country.data[[i]]), replace = TRUE, prob = c(0.7, 0.3))
  train[[i]] <- country.data[[i]][ind[[i]]==1,]
  test[[i]] <- country.data[[i]][ind[[i]]==2,]
  
  'rf[[i]] <- ranger(SCHOOLS ~ x + y + land + pop + built_s + built_v + smod.10 + smod.11 + smod.12 + smod.13 + smod.21 + smod.22 + smod.23 + smod.30, 
                data = train[[i]], 
                respect.unordered.factors = "order",
                seed = 23)'
  
  
  #saveRDS(rf[[i]], file = paste("Outputs/", countries[[i]], "_10km_school_indicator_RF_AllVars_ghsl.rds", sep = ""))
  #rf[[i]] <- readRDS(file = paste("Outputs/", countries[[i]], "_10km_school_indicator_RF_AllVars_ghsl.rds", sep = ""))
  
}

rf <- list()
for(i in 1:14){
  rf[[i]] <- readRDS(file = paste("Outputs/", countries[[i]], "_10km_school_indicator_RF_AllVars_ghsl.rds", sep = ""))
  
  print(rf[[i]])
  print(sqrt(rf[[i]]$prediction.error))
}


## Model Tuning

'For a Random Forest classification model using the RandomForest package, the default hyperparameter variables are:
- $n_features = number of model covariates$
- $mtry = floor(sqrt(n_features))$
- $replace = TRUE$
- $min.node.size = 1$
- $sample.fraction$ from data set-Up
- $ntree = 500$

We consider a grid of alternative hyperparamters:
- $n_features = number of model covariates$
- $mtry = c(seq(1, n_features, 1))$
- $replace = c(TRUE, FALSE)$
- $min.node.size = c(seq(1, n_features, 1))$
- $sample.fraction = c(0.5, 0.632, 0.7, 0.8, 0.9)$
- $ntree = c(n_features*10, 100, 200, 500, 1000)$'



n_features <- 14

hyper_grid <- expand.grid(
  mtry = c(seq(1, n_features, 1)), 
  min.node.size = c(seq(1, n_features, 1)),
  replace = c(TRUE, FALSE),
  sample.fraction = c(0.5, 0.632, 0.7, 0.8, 0.9, 1),
  num.trees = c(n_features*10, 50, 100, 200, 500),
  rmse = NA
)

'Using a full grid search for each country, we run the model tuning. 
We aim to find the hyperparameter values that minimise the model RMSE.
Then fit this model and report statistics'


set.seed(23)

tuned_hyper <- list()
hyper_grid_list <- list()
rf2 <- list()
for (i in 7:7){ #1:length(countries)){
  hyper_grid_list[[i]] <- hyper_grid
  
  for(j in seq_len(nrow(hyper_grid_list[[i]]))){
    set.seed(23)
    
    fit <- ranger(SCHOOLS ~ x + y + land + pop + built_s + built_v + smod.10 + smod.11 + smod.12 + smod.13 + smod.21 + smod.22 + smod.23 + smod.30, 
                  data = country.data[[i]],
                  num.trees = hyper_grid_list[[i]]$num.trees[j],
                  mtry = hyper_grid_list[[i]]$mtry[j],
                  min.node.size = hyper_grid_list[[i]]$min.node.size[j],
                  replace = hyper_grid_list[[i]]$replace[j],
                  sample.fraction = 1, #hyper_grid_list[[i]]$sample.fraction[j],
                  verbose = FALSE,
                  seed = 23,
                  respect.unordered.factors = 'order'
    )
    hyper_grid_list[[i]]$rmse[j] <- sqrt(fit$prediction.error)
  }
  
  default_rmse <- sqrt(rf[[i]]$prediction.error)
  
  tuned_hyper[[i]] <- hyper_grid_list[[i]] %>% arrange(rmse) %>%
    head(1)
  
  tuned_hyper[[i]]$default_rmse <- sqrt(rf[[i]]$prediction.error)
  
  print(tuned_hyper[[i]])
  
  set.seed(23)
  rf2[[i]] <- ranger(SCHOOLS ~ x + y + land + pop + built_s + built_v + smod.10 + smod.11 + smod.12 + smod.13 + smod.21 + smod.22 + smod.23 + smod.30, 
                     data = train[[i]],
                     mtry = tuned_hyper[[i]][1,1], 
                     min.node.size = tuned_hyper[[i]][1,2], 
                     replace = tuned_hyper[[i]][1,3], 
                     sample.fraction = tuned_hyper[[i]][1,4],
                     num.trees = tuned_hyper[[i]][1,5],
                     respect.unordered.factors = "order",
                     seed = 23
                     
  )
  
  tuned_hyper[[i]]$rmse.final <- sqrt(rf2[[i]]$prediction.error)
  tuned_hyper[[i]]$perc_gain <- (tuned_hyper[[i]]$default_rmse - tuned_hyper[[i]]$rmse.final) / tuned_hyper[[i]]$default_rmse * 100
  
  
  #saveRDS(tuned_hyper[[i]], file = paste("Outputs/", countries[[i]], "_10km_school_indicator_RF_Tuned_Hyperparameters.rds", sep = ""))
  #saveRDS(rf2[[i]], file = paste("Outputs/", countries[[i]], "_10km_school_indicator_RF_Tuned.rds", sep = ""))
  
  print(countries[[i]])
  print(rf2[[i]])
  print(tuned_hyper[[i]]$default_rmse)
  print(tuned_hyper[[i]])
  print("END")
  
}

for (i in 1:14){
  
  tuned_hyper[[i]] <- readRDS(file = paste("Outputs/", countries[[i]], "_10km_school_indicator_RF_Tuned_Hyperparameters.rds", sep = ""))
  rf2[[i]] <- readRDS(file = paste("Outputs/", countries[[i]], "_10km_school_indicator_RF_Tuned.rds", sep = ""))
  print(countries[[i]])
  print(rf2[[i]])
  print(tuned_hyper[[i]]$default_rmse)
  print(tuned_hyper[[i]])
  print("END")
}


## Prediction 

'Using the model prediction function, we can predict 4 different values:
1. Prediction on training set
2. Prediction on testing set
3. Prediction on entire country data

We can then view the confusion matrix and model statistics, including:

- Confusion Matrix
- Accuracy
- 95\% CI
- No info rate
- p-value (acc > nir)
- kappa
- Mcnemars Test P-Value
- sensitivity
- Specificity
- pos pred value
- neg pred value
- prevalence
- detection rate
- detection prevalence
- balanced accuracy
- positive class'



Africa <- st_read(dsn = "Data/Africa_Shapefile/Africa_Boundaries.shp")
st_crs(Africa)
#Africa <- st_transform(Africa, crs = "ESRI:54009")

head(Africa)

p1 <- list()
trained <- list()
p2 <- list()
tested <- list()
p3 <- list()
predicted <- list()
#AOI <- list()
Africa_54009 <- st_transform(Africa, crs = "ESRI:54009")
AOI <- subset(Africa_54009, ISO %in% countries)

pred.data <- list()
predicted.r <- list()
pred.sf <- list()

for (i in 1:length(countries)){
  p1[[i]] <- predict(rf2[[i]], train[[i]])
  trained[[i]] <- cbind(p1[[i]]$predictions, train[[i]])
  names(trained[[i]])[1] <- "p1"
  confusionMatrix(trained[[i]]$p1, train[[i]]$SCHOOLS)
  
  p2[[i]] <- predict(rf2[[i]], test[[i]])
  tested[[i]] <- cbind(p2[[i]]$predictions, test[[i]])
  names(tested[[i]])[1] <- "p2"
  confusionMatrix(tested[[i]]$p2, test[[i]]$SCHOOLS)
  print(countries[[i]])
  print(confusionMatrix(tested[[i]]$p2, test[[i]]$SCHOOLS))
  
  p3[[i]] <- predict(rf2[[i]], country.data[[i]])
  predicted[[i]] <- cbind(p3[[i]]$predictions, country.data[[i]])
  names(predicted[[i]])[1] <- "p3"
  confusionMatrix(predicted[[i]]$p3, country.data[[i]]$SCHOOLS)
  predicted[[i]]$diff <- as.factor(as.numeric(predicted[[i]]$p3) - as.numeric(predicted[[i]]$SCHOOLS))
  
  
  #AOI[[i]] <- subset(Africa, ISO3 == countries[[i]])
  #AOI[[i]] <- st_transform(AOI[[i]], crs = "ESRI:54009")
  
  pred.sf[[i]] <- st_as_sf(predicted[[i]], coords = c("x","y"), crs = "ESRI:54009")
  pred.country <- st_intersection(pred.sf[[i]], AOI)
  
  pred.data[[i]] <- cbind(st_drop_geometry(pred.country), st_coordinates(pred.country))

  saveRDS(pred.data[[i]], file = paste("Outputs/", countries[[i]], "_10km_school_indicator_RF_Pred_Data.rds", sep = ""))
  
}

pred.all <- do.call(rbind, pred.data)

saveRDS(pred.all, file = "Outputs/Africa_10km_school_count_RF_Pred.RDS")



'From prediction 3., we can create the gridded prediction as a raster'



names(pred.data[[1]])
predicted.r <- list()
for (i in 1:length(countries)){
  data <- pred.data[[i]][,c(25,26,1:24)]
  predicted.r[[i]] <- rast(data, type = "xyz", crs = "ESRI:54009")
  country.r <- predicted.r[[i]]
  saveRDS(country.r, file = paste("Outputs/", countries[[i]], "_10km_school_count_RF_Pred_Raster.RDS", sep = ""))
  
}
plot(predicted.r[[1]])



'We report the confusion matrices, accuracy, precision, kappa'

## change this
head(confusionMatrix(trained[[i]]$p1, train[[i]]$SCHOOLS))

CM <- list()
S <- list()
for (i in 1:length(countries)){
  CM[[i]] <- list()
  S[[i]] <- list()
  
  CM[[i]][[1]] <- confusionMatrix(trained[[i]]$p1, train[[i]]$SCHOOLS)$table
  S[[i]][[1]] <- confusionMatrix(trained[[i]]$p1, train[[i]]$SCHOOLS)$overall[1]
  S[[i]][[2]] <- confusionMatrix(trained[[i]]$p1, train[[i]]$SCHOOLS)$byClass[1]
  S[[i]][[3]] <- confusionMatrix(trained[[i]]$p1, train[[i]]$SCHOOLS)$byClass[2]
  
  CM[[i]][[2]] <- confusionMatrix(tested[[i]]$p2, test[[i]]$SCHOOLS)$table
  S[[i]][[4]] <- confusionMatrix(tested[[i]]$p2, test[[i]]$SCHOOLS)$overall[1]
  S[[i]][[5]] <- confusionMatrix(tested[[i]]$p2, test[[i]]$SCHOOLS)$byClass[1]
  S[[i]][[6]] <- confusionMatrix(tested[[i]]$p2, test[[i]]$SCHOOLS)$byClass[2]
  
  CM[[i]][[3]] <- confusionMatrix(predicted[[i]]$p3, country.data[[i]]$SCHOOLS)$table
  S[[i]][[7]] <- confusionMatrix(predicted[[i]]$p3, country.data[[i]]$SCHOOLS)$overall[1]
  S[[i]][[8]] <- confusionMatrix(predicted[[i]]$p3, country.data[[i]]$SCHOOLS)$byClass[1]
  S[[i]][[9]] <- confusionMatrix(predicted[[i]]$p3, country.data[[i]]$SCHOOLS)$byClass[2]
  
}

CM
S




'And:

4. Probability prediction on entire country data

First we fit the Random Forest using `probability = TRUE` in the ranger function.
Then one loop we also create the gridded predictions as a raster and consider different thresholds of the predictive probabilities.
This is to create a priority order for other work. We consider significance at 6 different levels: 20%, 10%, 5%, 2.5%, 1%, 0.1%'





rf3 <- list()
for (i in 1:length(countries)) {
  rf3[[i]] <- ranger(SCHOOLS ~ x + y + land + pop + built_s + built_v + smod.10 + smod.11 + smod.12 + smod.13 + smod.21 + smod.22 + smod.23 + smod.30, 
                     data = train[[i]],
                     mtry = tuned_hyper[[i]][1,1], 
                     min.node.size = tuned_hyper[[i]][1,2], 
                     replace = tuned_hyper[[i]][1,3], 
                     num.trees = tuned_hyper[[i]][1,5],
                     respect.unordered.factors = "order",
                     probability = TRUE,
                     seed = 23
  )
  
  tuned_hyper[[i]]$rmse.final.prob <- sqrt(rf3[[i]]$prediction.error)
  
  saveRDS(rf3[[i]], file = paste("Outputs/", countries[[i]], "_10km_school_count_RF_Pred.rds", sep = ""))
  
}

p4 <- list()
predicted.probs <- list()
prob.pred <- list()
prob.pred.r <- list()
for (i in 1:length(countries)){
  p4[[i]] <- predict(rf3[[i]], country.data[[i]])
  predicted.probs[[i]] <- cbind(p4[[i]]$predictions, country.data[[i]])
  names(predicted.probs[[i]])[c(1,2)] <- c("prob_0", "prob_1")
  
  pred.sf <- st_as_sf(predicted.probs[[i]], coords = c("x","y"), crs = "ESRI:54009")
  st_crs(pred.sf) <- "ESRI:54009"
  pred.country <- st_intersection(pred.sf, AOI)
  pred.data <- cbind(st_drop_geometry(pred.country), st_coordinates(pred.country))
  
  pred.prob.r <- rast(predicted.probs[[i]][,c(4,5,1,2,3,6:21)], type = 'xyz', crs = "ESRI:54009")
  pred.prob.data <- as.data.frame(pred.prob.r, cell = TRUE, xy = TRUE)
  
  pred.prob.data$pred.schools <- ifelse(pred.prob.data$SCHOOLS == 1 | is.na(pred.prob.data$SCHOOLS), NA, pred.prob.data$prob_1)
  
  prob.r <- rast(pred.prob.data[,c(2,3,1,4:23)], type = 'xyz', crs = "+proj=moll +lon_0=0 +x_0=0 +y_0=0 +datum=WGS84 +units=m +no_defs +type=crs", digits = 6, extent = NULL)
  
  
  quant <- quantile(pred.prob.data[,"prob_1"], probs = c(0.8, 0.9, 0.95, 0.975, 0.99, 0.999, 1), na.rm = TRUE)
  
  pred.prob.data$sig.prob_0.2 <- ifelse(pred.prob.data$prob_1 < quant[1], NA, pred.prob.data$prob_1)
  pred.prob.data$sig.prob_0.1 <- ifelse(pred.prob.data$prob_1 < quant[2], NA, pred.prob.data$prob_1)
  pred.prob.data$sig.prob_0.05 <- ifelse(pred.prob.data$prob_1 < quant[3], NA, pred.prob.data$prob_1)
  pred.prob.data$sig.prob_0.025 <- ifelse(pred.prob.data$prob_1 < quant[4], NA, pred.prob.data$prob_1)
  pred.prob.data$sig.prob_0.01 <- ifelse(pred.prob.data$prob_1 < quant[5], NA, pred.prob.data$prob_1)
  pred.prob.data$sig.prob_0.001 <- ifelse(pred.prob.data$prob_1 < quant[6], NA, pred.prob.data$prob_1)
  
  prob.pred[[i]] <- pred.prob.data
  save(pred.prob.data, file = paste("Outputs/", countries[[i]], "_10km_school_count_RF_Pred_Prob.RData", sep = ""))
  
  prob.r <- rast(pred.prob.data[,c(2,3,1,4:29)], type = 'xyz', crs = "+proj=moll +lon_0=0 +x_0=0 +y_0=0 +datum=WGS84 +units=m +no_defs +type=crs", digits = 6, extent = NULL)
  prob.pred.r[[i]] <- prob.r
}

plot(prob.pred.r[[1]])





'Any of the cropping and mapping stuff?'