crossvalidate.new <- function(data, Y, D, X, CV.method='simple', FE=NULL, treat.type, Z = NULL, weights = NULL, cl = NULL, base=NULL, 
                              X.eval, grid, kfold = 10, parallel = TRUE, seed=NULL, bw.adaptive = F,
                              metric = "MSPE"){
  if(is.null(seed)==F){
    set.seed(seed)
  }
  ## %dopar% <- NULL
  requireNamespace('lfe')
  cat("Cross-validating bandwidth ... \n")
  ## generate 5 random folds
  ## if is.null(cluster)==false then fold by cluster
  n<-dim(data)[1]
  fold<-rep(0,n)
  
  if(CV.method=='cluster' & is.null(cl)==TRUE){
	stop("\"cl\" is not specified.")
  }
  
  if(CV.method=='simple'){
	kfold <- min(n,kfold)
    cat("kfold =",kfold)
    cat("\n")
    fold <- c(0:(n-1))%%kfold + 1
    fold<-sample(fold, n, replace = FALSE)
  }
  if(CV.method=='cluster' & is.null(cl)==FALSE){
	clusters<-unique(data[,cl])
    m <- length(clusters)
    kfold <- min(m,kfold)
	cat("Use clustered cross validation.\n")
    cat("kfold =",kfold)
	cat("\n")
    id.list<-split(1:n,data[,cl])
    cl.fold <- c(0:(m-1))%%kfold + 1
    cl.fold <- sample(cl.fold, m, replace = FALSE)
    for (i in 1:m) {
      id.list[[i]] <- rep(cl.fold[i],length(id.list[[i]]))
    }
    fold <- unlist(id.list)
  }
  if(CV.method=='stratify'){
	requireNamespace("caret")
	fold <- createFolds(factor(data[,D]), k = kfold, list = FALSE)
	cat("Use stratified cross validation.\n")
	cat("kfold =",kfold)
	cat("\n")
  }
  

  
  if(treat.type=='discrete') {
    all_treat <- unique(data[,D])
    if(is.null(base)==TRUE){
      base <- all_treat[1]
    }
    other_treat <- all_treat[which(all_treat!=base)]
  }
  
  if(treat.type=='discrete'){
    ## calculate error for testing set (discrete)
    getError.new <- function(train, test, bw, Y, X, D, Z=NULL, FE, weights, 
                             X.eval,treat.type='discrete'){
      if(is.null(weights)==T){
        w <- rep(1,dim(train)[1])
        w2 <- rep(1,dim(test)[1])
      }
      else{
        w <- train[,weights]
        w2 <- test[,weights]
      }
      add_FE <- rep(0,dim(test)[1])
      
      if(is.null(FE)==F){
      #demean
	  train_y <- as.matrix(train[,Y])
	  train_FE <- as.matrix(train[,FE])
	  
	  invisible(
		capture.output(
        fastplm_res <- fastplm(data = train_y,FE = train_FE,weight = w, FEcoefs = 1L),type='message'
		)
	  )
	  FEvalues <- fastplm_res$FEvalues
	  FEnumbers <- dim(fastplm_res$FEvalues)[1]
	  FE_coef <- matrix(FEvalues[,3],nrow = FEnumbers, ncol = 1)
	  rowname <- c()
	  for(i in 1:FEnumbers){
		rowname <- c(rowname,paste0(FE[FEvalues[i,1]+1],'.',FEvalues[i,2]))
	  }
	  rownames(FE_coef) <- rowname
	  #FE_coef <- as.array(FE_coef)

      train[,Y] <- fastplm_res$residuals
      
      #addictive FE
      add_FE <- matrix(0,nrow = dim(test)[1],ncol = length(FE))
      colnames(add_FE) <- FE
      for(fe in FE){
        for(i in 1:dim(test)[1]){
          fe_name <- paste0(fe,".",test[i,fe])
		  
          if(fe_name %in% rownames(FE_coef)){
            add_FE[i,fe] <- FE_coef[fe_name,]
			#print(FE_coef[fe_name,])
          }
          else{
            add_FE[i,fe] <- 0
          }
        }
      }
      add_FE <- rowSums(add_FE)
	  add_FE <- add_FE + fastplm_res$mu
      }

      #generate dummy variable
      test_d <- test[,c(Y,X)]
      for (char in other_treat) {
        test_d[,paste0("D.",char)] <- as.numeric(test[,D]==char)
      }
      
      #get coef
      coef<-coefs.new(data=train,bw=bw,Y=Y,X=X,D=D,Z=Z,base=base,treat.type = 'discrete',
                      weights = weights, X.eval= X.eval,bw.adaptive = bw.adaptive)
      coef[is.na(coef)] <- 0
      nZ<-length(Z)
      ntreat <- length(other_treat)
      
      esCoef<-function(x){ ##obtain the coefficients for x[i]
        Xnew<-abs(X.eval-x)
        d1<-min(Xnew)     ## distance between x[i] and the first nearest x in training set
        label1<-which.min(Xnew)
        Xnew[label1]<-Inf
        d2<-min(Xnew)     ## distance between x[i] and the second nearest x in training set
        label2<-which.min(Xnew)
        if(d1==0){
          if(is.null(Z)==T){
            func <- coef[label1,c(2:(2+ntreat))] # X.eval (1), intercept (2), d (3), xx (4), d:xx (5), z
          }
          else{
            func <- coef[label1,c(c(2:(2+ntreat)),c((2+2*ntreat+1+1):(2+2*ntreat+1+nZ)))] # X.eval (1), intercept (2), d (3), xx (4), d:xx (5), z  
          }
        }  
        else if(d2==0){
          if(is.null(Z)==T){
            func <- coef[label2,c(2:(2+ntreat))] 
          }
          else{
            func <- coef[label2,c(c(2:(2+ntreat)),c((2+2*ntreat+1+1):(2+2*ntreat+1+nZ)))] 
          }
        } 
        else{ ## weighted average 
          if(is.null(Z)==T){
            func1 <- coef[label1,c(2:(2+ntreat))] 
            func2 <- coef[label2,c(2:(2+ntreat))]
          }
          else{
            func1 <- coef[label1,c(c(2:(2+ntreat)),c((2+2*ntreat+1+1):(2+2*ntreat+1+nZ)))]
            func2 <- coef[label2,c(c(2:(2+ntreat)),c((2+2*ntreat+1+1):(2+2*ntreat+1+nZ)))]
          }
          func <- (func1 * d2 + func2 * d1)/(d1 + d2) 
        }
        return(func)
      }
      
      Knn<-t(sapply(test[,X],esCoef)) ## coefficients for test  class==matrix
      
      ## predicting
      test.Y <- test[,Y]
      test.X <- as.data.frame(rep(1,dim(test)[1]))
      
      for (char in other_treat) {
        test.X[,paste0("D.",char)] <- test_d[,paste0("D.",char)]
      }
      test.X <- cbind(test.X,as.data.frame(test[,Z]))
      test.X <- as.matrix(test.X)
      sumOfEst<-matrix(lapply(1:length(test.X), function(i){test.X[i]*Knn[[i]]}),
                       nrow=nrow(test.X), ncol=ncol(test.X))
      error <- test.Y - rowSums(matrix(unlist(sumOfEst),length(test.Y))) - add_FE  
      
      # weights
      error <- error*w2/mean(w2)
      
      return(c(mean(abs(error)),mean(error^2)))
    }
  }
  
  if(treat.type=='continuous'){
    
    getError.new <- function(train, test, bw, Y, X, FE, D, Z=NULL, weights, X.eval, treat.type='continuous'){
      
      if(is.null(weights)==T){
        w <- rep(1,dim(train)[1])
        w2 <- rep(1,dim(test)[1])
      }
      else{
        w <- train[,weights]
        w2 <- test[,weights]
      }
      
      #demean
      add_FE <- rep(0,dim(test)[1])
      
      if(is.null(FE)==F){
      #demean
	  train_y <- as.matrix(train[,Y])
	  train_FE <- as.matrix(train[,FE])
	  
	  invisible(
		capture.output(
        fastplm_res <- fastplm(data = train_y,FE = train_FE,weight = w, FEcoefs = 1L),type='message'
		)
	  )
	  FEvalues <- fastplm_res$FEvalues
	  FEnumbers <- dim(fastplm_res$FEvalues)[1]
	  FE_coef <- matrix(FEvalues[,3],nrow = FEnumbers, ncol = 1)
	  rowname <- c()
	  for(i in 1:FEnumbers){
		rowname <- c(rowname,paste0(FE[FEvalues[i,1]+1],'.',FEvalues[i,2]))
	  }
	  rownames(FE_coef) <- rowname
	  #FE_coef <- as.array(FE_coef)

      train[,Y] <- fastplm_res$residuals
      
      #addictive FE
      add_FE <- matrix(0,nrow = dim(test)[1],ncol = length(FE))
      colnames(add_FE) <- FE
      for(fe in FE){
        for(i in 1:dim(test)[1]){
          fe_name <- paste0(fe,".",test[i,fe])
		  
          if(fe_name %in% rownames(FE_coef)){
            add_FE[i,fe] <- FE_coef[fe_name,]
			#print(FE_coef[fe_name,])
          }
          else{
            add_FE[i,fe] <- 0
          }
        }
      }
      add_FE <- rowSums(add_FE)
	  add_FE <- add_FE + fastplm_res$mu
      }
      
      coef<-coefs.new(data=train,bw=bw,Y=Y,X=X,D=D,Z=Z,treat.type = 'continuous',bw.adaptive = bw.adaptive,
                      weights = weights, X.eval= X.eval)
      coef[is.na(coef)] <- 0
      n2<-length(Z)
      esCoef<-function(x){ ##obtain the coefficients for x[i]
        Xnew<-abs(X.eval-x)
        d1<-min(Xnew)     ## distance between x[i] and the first nearest x in training set
        label1<-which.min(Xnew)
        Xnew[label1]<-Inf
        d2<-min(Xnew)     ## distance between x[i] and the second nearest x in training set
        label2<-which.min(Xnew)
        if(d1==0){
          func <- coef[label1,-c(1,4,5)] # X.eval (1), intercept (2), d (3), xx (4), d:xx (5), z
        }  else if(d2==0){
          func <- coef[label2,-c(1,4,5)]  
        } else{ ## weighted average 
          func <- (coef[label1,-c(1,4,5)] * d2 + coef[label2,-c(1,4,5)] * d1)/(d1 + d2) 
        }
        return(func)
      } 
      Knn<-t(sapply(test[,X],esCoef)) ## coefficients for test  class==matrix
      
      ## predicting
      test.Y <- test[,Y]
      test.X <- as.matrix(cbind(rep(1,dim(test)[1]),test[,c(D,Z)])) 
      sumOfEst<-matrix(lapply(1:length(test.X), function(i){test.X[i]*Knn[[i]]}),
                       nrow=nrow(test.X), ncol=ncol(test.X))
      error<-test.Y - rowSums(matrix(unlist(sumOfEst),length(test.Y)))-add_FE
      
      # weights
      error <- error*w2/mean(w2)
      return(c(mean(abs(error)),mean(error^2)))
    } 
  }
  
  
  ## grid search and k fold cross-validation
  cv.new<-function(bw){
    mse<-matrix(NA,kfold,2)
    for(j in 1:kfold){ # 5-fold CV
      testid <- which(fold==j)
      train <- data[-testid,]
      test <- data[testid, ]

      mse[j,] <- getError.new(train= train, test = test, treat.type = treat.type,FE=FE,
                              bw = bw, Y=Y, X=X, D=D, Z=Z, weights = weights, X.eval= X.eval)
    }
    return(c(bw, apply(mse,2,mean)))
  }
  
  
  ## calculation
  if (parallel == TRUE) {

    
    Error<-suppressWarnings(foreach(bw = grid, .combine = rbind,
                                    .export = c("coefs.new","getError.new"),
                                    .inorder = FALSE) %dopar% {cv.new(bw)})
 
  } 
  else {
    Error <- matrix(NA, length(grid), 3)
    for (i in 1:length(grid)) {
      Error[i, ] <- cv.new(grid[i])
      cat(".")
    } 
  } 
  colnames(Error) <- c("bandwidth","MAPE","MSPE")
  rownames(Error) <- NULL
  
  if (metric=="MAPE") {
    opt.bw <- grid[which.min(Error[,2])]
  } 
  else {
    opt.bw <- grid[which.min(Error[,3])]
  } 

  output <- list(CV.out = round(Error,3),
                   opt.bw = opt.bw)
  cat(paste("Bandwidth =", round(output$opt.bw,3),"\n"))
  
  return(output)
}




























