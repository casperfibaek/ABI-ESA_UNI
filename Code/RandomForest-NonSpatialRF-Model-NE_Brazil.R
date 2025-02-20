
# Random Forest Regression for School Counts

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
library(rmarkdown)
library(ggpubr)


### Load in Data

'Africa grids 10km x 10km using GHSL grids and data

Set seed'



setwd("/home/azureuser/cloudfiles/code/Users/ariley")
setwd("C:/Users/air21/Documents/UNICEF-ESA/Code/FINAL")


grid_data <- read.csv("Data/NE_10km_school_count_wData.csv")

set.seed(23)
random.seed <- 23



## Individual African Country Models

### Set-Up Data

'Load in data, remove any missing data, name the variables something slightly more sensible, specify countries, and create factor indicator for schools/no schools.

Define output and predictor variables

We also need all the variables to be numeric, in this case.'



data <- grid_data[,-1]
data <- na.omit(data)
head(data)
data$SCHOOLS <- as.factor(ifelse(data$NUMPOINTS > 0, 1, 0))

dependent.variable.name <- "NUMPOINTS"
predictor.variable.names <- colnames(data)[c(4:15)]

data[,dependent.variable.name] <- as.numeric(data[,dependent.variable.name])

for(i in 1:12){
  print(class(data[,predictor.variable.names[i]]))
  data[,predictor.variable.names[[i]]] <- as.numeric(data[,predictor.variable.names[[i]]])
  
}



### Set-Up Spatial Terms

'We take the coordinates as `x` and `y`

And define the distance matrix as the distances between all points

Note: Here we consider just the centroids of the grid cells

We also create a small vector of distance thresholds, a sequence of distances we evaluate spatial autocorrelation at.
We are working in metres.'



xy <- data[, c("x", "y")]

#distance.matrix <- as.matrix(dist(xy), ncol = nrow(xy))
#head(distance.matrix)

distance.thresholds <- c(0, 10000, 20000, 40000, 80000, 160000, 320000)

#save(distance.matrix, file = "Data/Schools/School_Counts/NE_10km_distance_matrix.RData")

#load(file = "Data/Schools/School_Counts/NE_10km_distance_matrix.RData")




## Check multicollinearity

'We can test for potential multicollinearity between the model variables.

We specify our own preference order, highlighting that `land` and `pop` are likely to be the biggest drives.

We set the correlation threshold as 0.6 and the variance inflation factor threshold as 2.5.

We repeat this for each country individually'



preference.order <- c(
  "land", "pop", "built_s", "built_v",
  "smod.30", "smod.23", "smod.22", "smod.21", "smod.13", "smod.12", "smod.11", "smod.10"
)

predictor.variable.names <- spatialRF::auto_cor(
  x = data[, predictor.variable.names],
  cor.threshold = 0.6,
  preference.order = preference.order 
) %>% 
  spatialRF::auto_vif(
    vif.threshold = 2.5,
    preference.order = preference.order
  )


predictor.variable.names$selected.variables



'We update our predictors and remove any redundant variables

## Fit Initial Non-Spatial Random Forest Regression Models

Straight forward implementation with the `spatialRF` package with default parameters'



model.non.spatial <- spatialRF::rf(
  data = data,
  dependent.variable.name = dependent.variable.name,
  predictor.variable.names = predictor.variable.names,
  #distance.matrix = distance.matrix,
  distance.thresholds = distance.thresholds,
  xy = xy, 
  seed = random.seed,
  verbose = FALSE
)
save(model.non.spatial, file = "Outputs/NE_Brazil_10km_school_count_nonspatialRF_model.RData")

load(file = "Outputs/NE_Brazil_10km_school_count_nonspatialRF_model.RData")

model.non.spatial

## Model Tuning

'We first used the default

We consider a grid of alternative hyperparamters:
- $n_features = number of model covariates$
- $mtry = c(seq(1, n_features, 1))$
- $min.node.size = c(seq(1, n_features, 1))$
- $num.trees = c(100, 200, 500, 1000)$

Using the `rf_tuning` function, which will find the best hyperparameter values and update the non-spatial model.'


install.packages("reprex")
reprex::reprex()

library(doParallel)
#Find out how many cores are available (if you don't already know)
cores<-detectCores()
#Create cluster with desired number of cores, leave one open for the machine         
#core processes
cl <- makeCluster(8) #cores[1]-1)
#Register cluster
registerDoParallel(cl)

n_features <- length(predictor.variable.names$selected.variables)

model.non.spatial.tuned <- spatialRF::rf_tuning(
  model = model.non.spatial,
  xy = xy,
  repetitions = 30,
  mtry = c(1,3,5), 
  min.node.size = c(1,5),
  num.trees = c(n_features*10, 250, 500),
  seed = random.seed,
  verbose = TRUE,
  n.cores = 1
)

model.non.spatial.tuned

save(model.non.spatial.tuned, file = "Outputs/NE_Brazil_10km_school_count_nonspatialRF_tuned_model.RData")

load(file = "Outputs/NE_Brazil_10km_school_count_nonspatialRF_tuned_model.RData")



### Model Residuals

'We can see the diagnostic plots for the model Residuals'



spatialRF::plot_residuals_diagnostics(
  model.non.spatial.tuned,
  verbose = FALSE
)
ggsave("Outputs/NE_Brazil_10km_school_count_nonspatialRF_residuals.png")





## Variable Importance

### Global Variable Importance

'Using the inbuilt function we can define the global importance of each model variable according to the increase in mean error when it is removed from the model
'


spatialRF::plot_importance(
  model.non.spatial.tuned,
  verbose = FALSE
)
ggsave("Outputs/NE_Brazil_10km_school_count_nonspatialRF_importance.png")

importance.df <- randomForestExplainer::measure_importance(
  model.non.spatial.tuned,
  measures = c("mean_min_depth", "no_of_nodes", "times_a_root", "p_value")
)

kableExtra::kbl(
  importance.df %>% 
    dplyr::arrange(mean_min_depth) %>% 
    dplyr::mutate(p_value = round(p_value, 4)),
  format = "html"
) %>%
  kableExtra::kable_paper("hover", full_width = F)

head(model.non.spatial.tuned)



'Similarily, we can define local importance as the change in error per case.'



model.non.spatial.tuned <- spatialRF::rf_importance(
  model = model.non.spatial.tuned
)

names(model.non.spatial.tuned$importance)
head(model.non.spatial.tuned$importance$per.variable)
head(model.non.spatial.tuned$importance$local)

model.non.spatial.tuned$importance$per.variable %>% 
  ggplot2::ggplot() +
  ggplot2::aes(
    x = importance.oob,
    y = importance.cv
  ) + 
  ggplot2::geom_point(size = 3) + 
  ggplot2::theme_bw() +
  ggplot2::xlab("Importance (out-of-bag)") + 
  ggplot2::ylab("Contribution to transferability") + 
  ggplot2::geom_smooth(method = "lm", formula = y ~ x, color = "red4")

local.importance <- spatialRF::get_importance_local(model.non.spatial.tuned)

kableExtra::kbl(
  round(local.importance[1:10,], 2),
  format = "html"
) %>%
  kableExtra::kable_paper("hover", full_width = F)

local.importance <- cbind(
  xy,
  local.importance
)

head(local.importance)



'We can then plot the local importance of any of our variables'



Africa <- st_read(dsn = "Data/Africa_Shapefile/Africa_Boundaries.shp")
Africa_54009 <- st_transform(Africa, crs = "ESRI:54009")
NE_Brazil <- subset(Africa_54009, ISO == "BEN")

color.low <- viridis::viridis(3,option = "F")[2]
color.high <- viridis::viridis(3,option = "F")[1]

p1 <- ggplot(NE_Brazil) +
  geom_sf() + coord_sf() + 
  geom_raster(local.importance, mapping = aes(x = x, y = y, fill = land)) +
  scale_fill_gradient2(
    low = color.low, 
    high = color.high
  ) 

p2 <- ggplot(NE_Brazil) +
  geom_sf() + coord_sf() + 
  geom_raster(local.importance, mapping = aes(x = x, y = y, fill = pop)) +
  scale_fill_gradient2(
    low = color.low, 
    high = color.high
  ) 

p3 <- ggplot(NE_Brazil) +
  geom_sf() + coord_sf() + 
  geom_raster(local.importance, mapping = aes(x = x, y = y, fill = smod.23)) +
  scale_fill_gradient2(
    low = color.low, 
    high = color.high
  ) 


ggarrange(p1, p2, p3, ncol = 3)
ggsave("Outputs/NE_Brazil_10km_school_count_nonspatialRF_tuned_localimportance.png")




'We can also see things like response curves of the variables and the partial dependence plots'

{r}

spatialRF::plot_response_curves(
  model.non.spatial.tuned,
  quantiles = c(0.1, 0.5, 0.9),
  line.color = viridis::viridis(
    3, #same number of colors as quantiles
    option = "F", 
    end = 0.9
  ),
  ncol = 3, 
  show.data = TRUE
)

ggsave("Outputs/NE_Brazil_10km_school_count_nonspatialRF_tuned_responsecurves1.png")


spatialRF::plot_response_curves(
  model.non.spatial.tuned,
  quantiles = 0.5,
  ncol = 3
)

ggsave("Outputs/NE_Brazil_10km_school_count_nonspatialRF_tuned_responsecurves2.png")



#Partial dependence plots
pdp::partial(
  model.non.spatial.tuned, 
  train = data, 
  pred.var = "pop", 
  plot = TRUE, 
  grid.resolution = 1000
)

ggsave("Outputs/NE_Brazil_10km_school_count_nonspatialRF_tuned_partialdependencepop.png")


#Response curves
reponse.curves.df <- spatialRF::get_response_curves(model.non.spatial.tuned)

kableExtra::kbl(
  head(reponse.curves.df, n = 10),
  format = "html"
) %>%
  kableExtra::kable_paper("hover", full_width = F)

#Interactions

spatialRF::plot_response_surface(
  model.non.spatial.tuned,
  a = "pop",
  b = "land"
)

#or
pdp::partial(
  model.non.spatial.tuned, 
  train = data, 
  pred.var = c("pop", "land"), 
  plot = TRUE
)




## Model Performance



spatialRF::print_performance(model.non.spatial.tuned)



## Spatial Cross-Validation

'Another assessment of the non-spatial is performing spatial cross-validation.

By seperating the data in spatially indpendent folds, the model is fit on each training fold and predicted for the testing fold.

Here we aim to maximise R$^2$ and minimise RMSE.

We can plot the ... and see the model ...'



model.non.spatial.tuned <- spatialRF::rf_evaluate(
  model = model.non.spatial.tuned,
  xy = xy,         
  repetitions = 30,  
  training.fraction = 0.75,
  metrics = "r.squared",
  seed = random.seed,
  verbose = FALSE
)

save(model.non.spatial.tuned, file = "/home/azureuser/cloudfiles/code/Users/ariley/Data/Schools/Africa/School_Counts/Outputs/NE_Brazil_10km_school_count_nonspatialRF_tuned_model_final.RData")


spatialRF::plot_evaluation(model.non.spatial.tuned)

spatialRF::print_evaluation(model.non.spatial.tuned)






## Prediction 

'We can then straightfowardly perform prediction across the whole domain and plot it'



data$NonSpatial.pred <- stats::predict(
  object = model.non.spatial.tuned,
  data = data, type = "response"
)$predictions

ggplot(NE_Brazil) +
  geom_sf() + coord_sf() + 
  geom_raster(data, mapping = aes(x = x, y = y, fill = NonSpatial.pred)) +
  scale_fill_viridis_c()


save(data, file = "Outputs/NE_Brazil_10km_school_count_data_with_model_pred.RData")



