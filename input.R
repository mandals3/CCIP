source("rfunc.R")

### program control: parameter choice for data generation

pc= list(n0= 100,          # number of controls
         n1= 200,          # number of incident cases
         n2= 100,          # number of prevalent cases
#
# parameter choice for 10% censoring
         cens.inc.lambda= 5,      # used to generate incident censoring time
         cens.prev.lambda= 15,    # used to generate prevalent censoring time
#
         xi.a= 30,                       # used in A ~ Unif(0, xi.a)
         rho= 0.5,                       # correlation between covariates
         xnames.gamma= c("x1", "x2"),
         xnames.beta= c("x1", "x2"),
#
# parameters in the logistic model
         alpha= -0.5,
         nu= 0.5,
         beta1= 1.0,
         beta2= -1.0,
#
#
         k1.shape= 1,           # shape for weibull baseline hazard
         k2.scale= 1,           # scale for weibull baseline hazard
         gamma1= 1,             # gammas for weibull baseline hazard
         gamma2= -1,
#
         init.gamma= c(1, -1, 1, 1),     # starting values: gamma_1, gamma_2, k1, k2
         init.beta= c(-0.5, 0.5, 1, -1)) # starting values: alpha, nu, beta_1, beta_2

### main function that returns the following estimates
### "Two-step EM" which is the proposed method,
### and also for comparison purposes: "Two-step Cox", "Joint Weibull",
### "IPCC" (using Weibull), "IPCC-Exp" (using Exponential for sensitivity analysis), 
### "Logistic Naive" and "Logistic IC"

output= final.out(pc,seed=1)
