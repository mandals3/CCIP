require(MASS)
require(survival)

### data generation under Weibull
### X from MVN, censoring: Uniform

generate.data.retrospectively= function(pc){

    N= pc$n0+ pc$n1+ pc$n2

    sigma=  matrix(c(1, pc$rho, pc$rho, 1), byrow= T, nrow= 2)
    betas= c(pc$beta1, pc$beta2)
    gammas= c(pc$gamma1, pc$gamma2)
    k1= pc$k1.shape
    k2= pc$k2.scale

### generate n0 controls
    x12.0= mvrnorm(n= pc$n0, mu= c(0, 0), Sigma= sigma)

### generate n1 incident cases
    nsize1= pc$n1*100
    x12.1.temp= mvrnorm(n= nsize1, mu= c(0, 0), Sigma= sigma)

    exp.xb= exp(x12.1.temp%*%betas)
    wt.inc= exp.xb/sum(exp.xb)
    sam.inc= sample((1:nsize1),pc$n1,replace=TRUE,prob=wt.inc)
    x12.1= x12.1.temp[sam.inc,]

    inci.true.time= k2*(-log(1-runif(pc$n1))/exp(x12.1%*%gammas))^(1/k1)
    cens.time= runif(pc$n1,0,pc$cens.inc.lambda)
    inc.obs.time= pmin(inci.true.time, cens.time)
    inc.del= as.numeric(inci.true.time <= cens.time)        # 1 if uncensored

### generate n2 prevalent cases
    nsize2= pc$n2*10000
    nsize22= nsize2/100
    x12.2.temp2= mvrnorm(n= nsize2, mu= c(0, 0), Sigma= sigma)

    exp.xb2= exp(x12.2.temp2%*%betas)
    wt.inc2= exp.xb2/sum(exp.xb2)
    sam.inc2= sample((1:nsize2),nsize22,replace=TRUE,prob=wt.inc2)
    x12.2.temp= x12.2.temp2[sam.inc2,]

    prev.true.time= k2*(-log(1-runif(nsize22))/exp(x12.2.temp%*%gammas))^(1/k1)
    backward.time.n2= runif(nsize22,0,pc$xi.a)
    pv.gr.ix= which(prev.true.time>backward.time.n2)
    pv.t.ix= sample(pv.gr.ix,pc$n2,replace=F)
    n2data= cbind(prev.true.time,backward.time.n2,x12.2.temp)
    prev.time= n2data[pv.t.ix,1]
    backward.time.n2= n2data[pv.t.ix,2]
    x12.2= n2data[pv.t.ix,-(1:2)]
    prev.forward.time= prev.time-backward.time.n2

### censoring the forward time
    cens.prev.time= runif(pc$n2,0,pc$cens.prev.lambda)
    prev.del= as.numeric(prev.forward.time <= cens.prev.time)        # 1 if uncensored

    prevn.obs.time= backward.time.n2+pmin(prev.forward.time,cens.prev.time)
    backward.time= c(rep.int(0, pc$n0 + pc$n1), backward.time.n2)

    follow.time= c(rep.int(0,pc$n0),inc.obs.time,prevn.obs.time)
    del= c(rep.int(0,pc$n0),inc.del,prev.del)

    case.status= c(rep.int(0, pc$n0), rep.int(1, pc$n1), rep.int(2, pc$n2))
    x12= rbind(x12.0, x12.1, x12.2)

    d= cbind(case.status, backward.time, follow.time, del, x12)
    colnames(d)= c('case.status', 'backward.time', 'follow.time', 'del', 'x1', 'x2')

    return(mydata = data.frame(d))
}


### used inside sweep function in lambda calculation
### aa= scalar and bb= vector works
eqfun= function(aa,bb)
    return(ifelse(aa==bb,1,0))

leqfun= function(aa,bb)
    return(ifelse(aa<=bb,1,0))


### estimating survival parameters using EM with incident and prevalent cases together
semipar.surv.icpv= function(mydata,x.col.ix.gamma){

    cont.ix= which(mydata[,'case.status']==0)
    myn0= length(cont.ix)

    ic.ix= which(mydata[,'case.status']==1)
    myn1= length(ic.ix)

    pv.ix= which(mydata[,'case.status']==2)
    pv.a= mydata[pv.ix,'backward.time']
    myn2= length(pv.ix)

    N= myn0+myn1+myn2
    len.x.col= length(x.col.ix.gamma)

    icpv.ix= which(mydata[,"case.status"]==1 | mydata[,"case.status"]==2)
    icpv.time= mydata[icpv.ix,'follow.time']
    icpv.time.sort= sort(icpv.time)
    icpv.time.order= order(icpv.time)
    icpv.del= mydata[icpv.ix,'del'][icpv.time.order]
    icpv.x= matrix(unlist(mydata[icpv.ix,x.col.ix.gamma]), ncol=len.x.col, byrow=F)[icpv.time.order,]
    all.x= matrix(unlist(mydata[,x.col.ix.gamma]), ncol=len.x.col, byrow=F)

    tt= unique(icpv.time.sort)
    lensp= length(tt)
    len= length(icpv.time.sort)
    tau= max(icpv.time.sort)

    ic.time= mydata[ic.ix,'follow.time']
    ic.time.sort= sort(ic.time)
    pv.time= mydata[pv.ix,'follow.time']
    pv.time.sort= sort(pv.time)

    match.ic.icpv= match(ic.time.sort,icpv.time.sort)
    match.pv.icpv= match(pv.time.sort,icpv.time.sort)

    tempcox1= coxph(Surv(icpv.time.sort,icpv.del)~icpv.x)
    gammaes3= as.vector(tempcox1$coef)
    gammaold= gammaes3

    ximat= matrix(rep(icpv.time.sort,length(tt)),nrow=len,byrow=F)
    xi.eq.tj.mat= sweep(ximat,2,tt,FUN=eqfun)
    sumi.del.xi.eq.tj.mat= apply(icpv.del*xi.eq.tj.mat,2,sum)

    ttd= c(tt[1],diff(tt))
    lambdaold= ttd/mean(icpv.time.sort)
    lambdanew= rep(0,lensp)

    gamma= gammaold
    lambda= lambdaold
    exp.xgamma= exp(as.vector(icpv.x%*%gamma))

    pij.mat1= matrix(exp.xgamma,len,1)%*%matrix(lambda,1,lensp)
    pij.mat2= matrix(exp.xgamma,len,1)%*%matrix(cumsum(lambda),1,lensp)
    pij.mat3= cbind(rep(0,len),pij.mat2[,-lensp])
    pij.mat= pij.mat1*exp(-pij.mat3)
    fmu= apply(sweep(pij.mat,2,tt,FUN="*"),1,sum)

    weight1.ic= matrix(0,myn1,lensp)
    weight1.pv= tau*sweep(pij.mat[match.pv.icpv,],2,(1-tt/tau),FUN="*")/fmu[match.pv.icpv]

    weight1= matrix(0,len,lensp)
    weight1[match.ic.icpv,]= weight1.ic
    weight1[match.pv.icpv,]= weight1.pv

    cov1= c(icpv.time.sort, rep(tt,len))
    cov2= c(icpv.del, rep(1,len*lensp))
    cov3= rbind(icpv.x, apply(icpv.x, 2, function(x) return(rep(x,each=lensp))))
    cov5= as.vector(t(weight1))
    cov6= c(rep(1,len), ifelse(cov5>0,cov5,min(cov5[cov5>0])))
    tempcox= coxph(Surv(cov1,cov2)~cov3,weights=cov6)

    gammanew= as.numeric(tempcox$coef)
    wexpbx= (weight1+xi.eq.tj.mat)*exp(as.vector(icpv.x%*%gammanew))
    sum.wexpbx= apply(wexpbx,2,sum)
    lambdanew= apply(weight1+xi.eq.tj.mat*icpv.del,2,sum)/rev(cumsum(rev(sum.wexpbx)))

    count= 1

#    while(max(abs(lambdanew-lambdaold))>0.001 & count<=200)
      while(max(abs(gammaold-gammanew))>0.001 & count<=200){
        gammaold= gammanew
        lambdaold= lambdanew
        gamma= gammaold
        lambda= lambdaold
        exp.xgamma= exp(as.vector(icpv.x%*%gamma))

        pij.mat1= matrix(exp.xgamma,len,1)%*%matrix(lambda,1,lensp)
        pij.mat2= matrix(exp.xgamma,len,1)%*%matrix(cumsum(lambda),1,lensp)
        pij.mat3= cbind(rep(0,len),pij.mat2[,-lensp])
        pij.mat= pij.mat1*exp(-pij.mat3)
        fmu= apply(sweep(pij.mat,2,tt,FUN="*"),1,sum)

        weight1.ic= matrix(0,myn1,lensp)
        weight1.pv= tau*sweep(pij.mat[match.pv.icpv,],2,(1-tt/tau),FUN="*")/fmu[match.pv.icpv]

        weight1= matrix(0,len,lensp)
        weight1[match.ic.icpv,]= weight1.ic
        weight1[match.pv.icpv,]= weight1.pv
    
        cov1= c(icpv.time.sort, rep(tt,len))
        cov2= c(icpv.del, rep(1,len*lensp))
        cov3= rbind(icpv.x, apply(icpv.x, 2, function(x) return(rep(x,each=lensp))))
        cov5= as.vector(t(weight1))
        cov6= c(rep(1,len), ifelse(cov5>0,cov5,min(cov5[cov5>0])))
        tempcox= coxph(Surv(cov1, cov2)~cov3, weights=cov6)

        gammanew= as.numeric(tempcox$coef)
        wexpbx= (weight1+xi.eq.tj.mat)*exp(as.vector(icpv.x%*%gammanew))
        sum.wexpbx= apply(wexpbx,2,sum)
        lambdanew= apply(weight1+xi.eq.tj.mat*icpv.del,2,sum)/rev(cumsum(rev(sum.wexpbx)))

        count= count+1
      }
#    }

    gammas= gammanew
    base.surv= exp(-cumsum(lambdanew))

    ind.icpv.less.xi= c(as.numeric(0<= tau), as.numeric(tt[-lensp]<= tau))
    exp.xg.all= exp(as.vector(all.x%*%gammas))
    icpv.time.diff= pmin(tt,tau)-c(0, tt[-lensp])
    ind.diff.prod= ind.icpv.less.xi*icpv.time.diff

    mu.surv.all= rep(0,N)
    for(i1 in 1:N)
      mu.surv.all[i1]= sum(ind.diff.prod*c(1,base.surv[-length(base.surv)])^exp.xg.all[i1])

    surv.out= list(mu.surv.all, gammas)
    return(surv.out)
}


### estimating survival parameters using coxph and incident and prevalent cases together
semipar.surv.icpv.cox= function(mydata,xnames.gamma){

    ic.ix= which(mydata[,'case.status']==1)
    pv.ix= which(mydata[,'case.status']==2)

    len.x.col= length(xnames.gamma)
    icpv.ix= which(mydata[,"case.status"]==1 | mydata[,"case.status"]==2)
    icpv.time= mydata[icpv.ix,'follow.time']
    icpv.time.sort= sort(icpv.time)
    icpv.time.order= order(icpv.time)

    mydata.icpv= mydata[icpv.ix,]
    tempcox= coxph(as.formula(paste("Surv(backward.time,follow.time,del)~",paste(xnames.gamma,collapse='+'))),data=mydata.icpv)

    gammas= as.numeric(tempcox$coef)
    cumsum.lambda= basehaz(tempcox, centered=FALSE)$hazard

    chazjumpid= which(cumsum.lambda[2:length(cumsum.lambda)]-cumsum.lambda[1:(length(cumsum.lambda)-1)]>0)

    tau= max(icpv.time.sort)
    tt= unique(icpv.time.sort)[chazjumpid]
    lensp= length(tt)
    ind.icpv.less.xi= c(as.numeric(0<= tau), as.numeric(tt[-lensp]<= tau))
    all.x= matrix(unlist(mydata[,xnames.gamma]), ncol=len.x.col, byrow=F)
    exp.xg.all= exp(as.vector(all.x%*%gammas))
    icpv.time.diff= pmin(tt,tau)-c(0, tt[-lensp])
    ind.diff.prod= ind.icpv.less.xi*icpv.time.diff

    N= length(mydata[,'follow.time'])
    mu.surv.all= rep(0,N)

    base.surv.cox= exp(-cumsum.lambda[chazjumpid])
    for(i1 in 1:N)
      mu.surv.all[i1]= sum(ind.diff.prod*c(1,base.surv.cox[-length(base.surv.cox)])^exp.xg.all[i1])

    surv.out= list(mu.surv.all, gammas)#, cumsum.lambda)
    return(surv.out)
}


### this function calculates the negative profile log-likelihood
neg.log.lik= function(mypar,mydata,x.col.ix.beta,surv.list){

    myalpha= mypar[1]
    mynu= mypar[2]
    mybeta= matrix(mypar[3:length(mypar)],ncol=1)
    len.x.col= length(x.col.ix.beta)

    ic.ix= which(mydata[,'case.status']==1)
    ic.x= matrix(unlist(mydata[ic.ix,x.col.ix.beta]), ncol=len.x.col, byrow=F)

    pv.ix= which(mydata[,'case.status']==2)
    pv.x= matrix(unlist(mydata[pv.ix,x.col.ix.beta]), ncol=len.x.col, byrow=F)

    all.x= matrix(unlist(mydata[,x.col.ix.beta]), ncol=len.x.col, byrow=F)
    all.x.beta= as.vector(all.x%*%mybeta)

    mu.surv.all= surv.list[[1]]

    lc1= -sum(log(1+ exp(myalpha+ all.x.beta)+ exp(mynu+ all.x.beta+ log(mu.surv.all))))
    lc2= sum(myalpha+ ic.x%*%mybeta)
    lc3= sum(mynu+ pv.x%*%mybeta)
    negloglik= -(lc1 + lc2 + lc3)

    return(negloglik)
}


### Single-step: full likelihood (survival + logistic) with Weibull
### using incident and prevalent cases together
neg.loglik.weibull.full= function(mypar,mydata,x.col.ix.gamma,x.col.ix.beta)
{

   ln.x.col.ix.gamma= length(x.col.ix.gamma)
   ln.x.col.ix.beta= length(x.col.ix.beta)

   myalpha= mypar[1]
   mynu= mypar[2]
   mybeta= mypar[3:(ln.x.col.ix.beta+2)]
   my.gamma= mypar[(ln.x.col.ix.beta+2+1):(ln.x.col.ix.beta+2+ln.x.col.ix.gamma)]
   wei.shape= mypar[ln.x.col.ix.beta+2+ln.x.col.ix.gamma+1]
   wei.scale= mypar[ln.x.col.ix.beta+2+ln.x.col.ix.gamma+2]

   xi= max(mydata[,"follow.time"])

### survival part

   i.ix= which(mydata[,"case.status"]==1)
   i.x= matrix(unlist(mydata[i.ix,x.col.ix.gamma]), ncol=length(x.col.ix.gamma), byrow=F)
   p.ix= which(mydata[,"case.status"]==2)
   p.x= matrix(unlist(mydata[p.ix,x.col.ix.gamma]), ncol=length(x.col.ix.gamma), byrow=F)
   ip.ix= which(mydata[,"case.status"]==1 | mydata[,"case.status"]==2)

   icpv.xgamma= matrix(unlist(mydata[ip.ix,x.col.ix.gamma]), ncol=length(x.col.ix.gamma), byrow=F)
   icpv.xgamma.gamma= icpv.xgamma%*%my.gamma
   exp.xgamma.icpv= exp(icpv.xgamma.gamma)
   exp.xgamma.pv= exp(p.x%*%my.gamma)

   neg.loglik.surv= -sum(mydata[ip.ix,"del"]*(icpv.xgamma.gamma+log(wei.shape)-log(wei.scale)+(wei.shape-1)*(log(mydata[ip.ix,"follow.time"])-
                    log(wei.scale)))-exp.xgamma.icpv*(mydata[ip.ix,"follow.time"]/wei.scale)^wei.shape)

### logistic part

   all.xbeta= matrix(unlist(mydata[,x.col.ix.beta]), ncol=length(x.col.ix.beta), byrow=F)
   ic.ix= which(mydata[,"case.status"]==1)
   ic.x= matrix(unlist(mydata[ic.ix,x.col.ix.beta]), ncol=length(x.col.ix.beta), byrow=F)
   pv.ix= which(mydata[,"case.status"]==2)
   pv.x= matrix(unlist(mydata[pv.ix,x.col.ix.beta]), ncol=length(x.col.ix.beta), byrow=F)
   all.xbeta.beta= all.xbeta%*%mybeta

   all.x.gamma= matrix(unlist(mydata[,x.col.ix.gamma]), ncol=length(x.col.ix.gamma), byrow=F)
   exp.xgamma= exp(all.x.gamma%*%my.gamma)

   mu.psi= exp.xgamma*wei.scale^(-wei.shape)
   wei.shape.inv= 1/wei.shape
   mu.up= xi^wei.shape

   mu.surv.part= rep(0,length(mu.psi))
   for(i1 in 1:length(mu.psi))
     mu.surv.part[i1]= pgamma(mu.up, shape= wei.shape.inv, rate= mu.psi[i1], lower.tail= TRUE)

   mu.surv.all= gamma(wei.shape.inv)*mu.surv.part/(wei.shape*mu.psi^wei.shape.inv)

   lc1= -sum(log(1+ exp(myalpha+ all.xbeta.beta)+ exp(mynu+ all.xbeta.beta+ log(mu.surv.all))))
   lc2= sum(myalpha+ ic.x%*%mybeta)
   lc3= sum(mynu+ pv.x%*%mybeta)              #+ surv.part)
   neg.loglik.logistic= -(lc1 + lc2 + lc3)

### combining

   neg.loglik= neg.loglik.surv + neg.loglik.logistic

   return(neg.loglik)
}


###############
### this is comparable to Maziarz et al.
### assuming Weibull baseline
### only using the backward time to maximize the logistic piece of the likelihood
### estimating both logistic and survival parameters
###############
neg.loglik.weibull.full2= function(mypar,mydata,x.col.ix.gamma,x.col.ix.beta){

   ln.x.col.ix.gamma= length(x.col.ix.gamma)
   ln.x.col.ix.beta= length(x.col.ix.beta)

   myalpha= mypar[1]
   mynu= mypar[2]
   mybeta= mypar[3:(ln.x.col.ix.beta+2)]
   my.gamma= mypar[(ln.x.col.ix.beta+2+1):(ln.x.col.ix.beta+2+ln.x.col.ix.gamma)]
   wei.shape= mypar[ln.x.col.ix.beta+2+ln.x.col.ix.gamma+1]
   wei.scale= mypar[ln.x.col.ix.beta+2+ln.x.col.ix.gamma+2]

   xi= max(mydata[,"backward.time"])

### survival part

   i.ix= which(mydata[,"case.status"]==1)
   i.x= matrix(unlist(mydata[i.ix,x.col.ix.gamma]), ncol=length(x.col.ix.gamma), byrow=F)
   p.ix= which(mydata[,"case.status"]==2)
   p.x= matrix(unlist(mydata[p.ix,x.col.ix.gamma]), ncol=length(x.col.ix.gamma), byrow=F)
   ip.ix= which(mydata[,"case.status"]==1 | mydata[,"case.status"]==2)

   icpv.xgamma= matrix(unlist(mydata[ip.ix,x.col.ix.gamma]), ncol=length(x.col.ix.gamma), byrow=F)
   icpv.xgamma.gamma= icpv.xgamma%*%my.gamma
   exp.xgamma.icpv= exp(icpv.xgamma.gamma)
   exp.xgamma.pv= exp(p.x%*%my.gamma)

### log of survival function
   surv.part= -exp.xgamma.pv*(mydata[p.ix,"backward.time"]/wei.scale)^wei.shape

### logistic part

   all.xbeta= matrix(unlist(mydata[,x.col.ix.beta]), ncol=length(x.col.ix.beta), byrow=F)
   ic.ix= which(mydata[,"case.status"]==1)
   ic.x= matrix(unlist(mydata[ic.ix,x.col.ix.beta]), ncol=length(x.col.ix.beta), byrow=F)
   pv.ix= which(mydata[,"case.status"]==2)
   pv.x= matrix(unlist(mydata[pv.ix,x.col.ix.beta]), ncol=length(x.col.ix.beta), byrow=F)
   all.xbeta.beta= all.xbeta%*%mybeta

   all.x.gamma= matrix(unlist(mydata[,x.col.ix.gamma]), ncol=length(x.col.ix.gamma), byrow=F)
   exp.xgamma= exp(all.x.gamma%*%my.gamma)

   mu.psi= exp.xgamma*wei.scale^(-wei.shape)
   wei.shape.inv= 1/wei.shape
   mu.up= xi^wei.shape

   mu.surv.part= rep(0,length(mu.psi))
   for(i1 in 1:length(mu.psi))
     mu.surv.part[i1]= pgamma(mu.up, shape= wei.shape.inv, rate= mu.psi[i1], lower.tail= TRUE)

   mu.surv.all= gamma(wei.shape.inv)*mu.surv.part/(wei.shape*mu.psi^wei.shape.inv)

   lc1= -sum(log(1+ exp(myalpha+ all.xbeta.beta)+ exp(mynu+ all.xbeta.beta+ log(mu.surv.all))))
   lc2= sum(myalpha+ ic.x%*%mybeta)
   lc3= sum(mynu+ pv.x%*%mybeta+ surv.part)
   neg.loglik.logistic= -(lc1 + lc2 + lc3)

   neg.loglik= neg.loglik.logistic

   return(neg.loglik)
}


###############
### this is Maziarz et al. misspecified
### assuming Exponential baseline
### only using the backward time to maximize the logistic piece of the likelihood
### estimating both logistic and survival parameters
###############
neg.loglik.full3.exp= function(mypar,mydata,x.col.ix.gamma,x.col.ix.beta){

   ln.x.col.ix.gamma= length(x.col.ix.gamma)
   ln.x.col.ix.beta= length(x.col.ix.beta)

   myalpha= mypar[1]
   mynu= mypar[2]
   mybeta= mypar[3:(ln.x.col.ix.beta+2)]
   my.gamma= mypar[(ln.x.col.ix.beta+2+1):(ln.x.col.ix.beta+2+ln.x.col.ix.gamma)]
   explambda= mypar[ln.x.col.ix.beta+2+ln.x.col.ix.gamma+1]

   xi= max(mydata[,"backward.time"])

### survival part

   i.ix= which(mydata[,"case.status"]==1)
   i.x= matrix(unlist(mydata[i.ix,x.col.ix.gamma]), ncol=length(x.col.ix.gamma), byrow=F)
   p.ix= which(mydata[,"case.status"]==2)
   p.x= matrix(unlist(mydata[p.ix,x.col.ix.gamma]), ncol=length(x.col.ix.gamma), byrow=F)
   ip.ix= which(mydata[,"case.status"]==1 | mydata[,"case.status"]==2)

   icpv.xgamma= matrix(unlist(mydata[ip.ix,x.col.ix.gamma]), ncol=length(x.col.ix.gamma), byrow=F)
   icpv.xgamma.gamma= icpv.xgamma%*%my.gamma
   exp.xgamma.icpv= exp(icpv.xgamma.gamma)
   exp.xgamma.pv= exp(p.x%*%my.gamma)

### log of survival function
   surv.part= -exp.xgamma.pv*(mydata[p.ix,"backward.time"]/explambda)

### logistic part

   all.xbeta= matrix(unlist(mydata[,x.col.ix.beta]), ncol=length(x.col.ix.beta), byrow=F)
   ic.ix= which(mydata[,"case.status"]==1)
   ic.x= matrix(unlist(mydata[ic.ix,x.col.ix.beta]), ncol=length(x.col.ix.beta), byrow=F)
   pv.ix= which(mydata[,"case.status"]==2)
   pv.x= matrix(unlist(mydata[pv.ix,x.col.ix.beta]), ncol=length(x.col.ix.beta), byrow=F)
   all.xbeta.beta= all.xbeta%*%mybeta

   all.x.gamma= matrix(unlist(mydata[,x.col.ix.gamma]), ncol=length(x.col.ix.gamma), byrow=F)
   exp.xgamma= exp(all.x.gamma%*%my.gamma)

   mu.psi= exp.xgamma*xi/explambda
   mu.surv.all= explambda*exp(-all.x.gamma%*%my.gamma)*(1-exp(-mu.psi))

   lc1= -sum(log(1+ exp(myalpha+ all.xbeta.beta)+ exp(mynu+ all.xbeta.beta+ log(mu.surv.all))))
   lc2= sum(myalpha+ ic.x%*%mybeta)
   lc3= sum(mynu+ pv.x%*%mybeta+ surv.part)
   neg.loglik.logistic= -(lc1 + lc2 + lc3)

   neg.loglik= neg.loglik.logistic

   return(neg.loglik)
}





### main function
final.out= function(pc,seed){

    set.seed(seed)
    d= generate.data.retrospectively(pc)

    ic.ix= which(d[,'case.status']==1)
    ic.del= d[ic.ix,'del']
    pv.ix= which(d[,'case.status']==2)
    pv.del= d[pv.ix,'del']
    icpv.ix= which(d[,"case.status"]==1 | d[,"case.status"]==2)
    perc.cens= (1-sum(c(ic.del,pv.del))/length(c(ic.ix,pv.ix)))*100
    perc.less.xi= sum(c(d[ic.ix,'follow.time'],d[pv.ix,'follow.time'])<pc$xi.a)*100/length(c(ic.ix,pv.ix))
    perc.ic.cens= (1-sum(ic.del)/length(ic.ix))*100
    perc.ic.less.xi= sum(d[ic.ix,'follow.time']<pc$xi.a)*100/length(ic.ix)
    perc.pv.cens= (1-sum(pv.del)/length(pv.ix))*100
    perc.pv.less.xi= sum(d[pv.ix,'follow.time']<pc$xi.a)*100/length(pv.ix)

    out.cen= c(perc.cens,perc.less.xi,perc.ic.cens,perc.ic.less.xi,perc.pv.cens,perc.pv.less.xi)

    xnames.gamma= pc$xnames.gamma
    xnames.beta= pc$xnames.beta
    x.col.ix.gamma= match(xnames.gamma, colnames(d))
    x.col.ix.beta= match(xnames.beta, colnames(d))

### two-step: EM
### step 1: gamma and mu
    surv.list= semipar.surv.icpv(d, x.col.ix.gamma)
### step 2: beta
    optim.out= optim(pc$init.beta, fn=neg.log.lik, method='BFGS', mydata=d, x.col.ix.beta=x.col.ix.beta, surv.list=surv.list, hessian=T)
    out.par= c(optim.out$par, surv.list[[2]])
    out.par.sd= optim.out$hessian

### two-step: Cox
### step 1: gamma and mu
    surv.list.cox= semipar.surv.icpv.cox(d, xnames.gamma)
### step 2: beta
    optim.cox= optim(pc$init.beta, fn=neg.log.lik, method='BFGS', mydata=d, x.col.ix.beta=x.col.ix.beta, surv.list=surv.list.cox, hessian=T)
    out.cox= c(optim.cox$par, surv.list.cox[[2]])
    out.cox.sd= optim.cox$hessian

### single-step: joint maximization of survival and logistic likelihood assuming Weibull baseline
    start.par= c(pc$init.beta, pc$init.gamma)
    wei.icpv.full= optim(start.par, fn=neg.loglik.weibull.full, method="L-BFGS-B",
                         lower=c(rep(-Inf,length(xnames.gamma)),rep(-Inf,length(pc$init.beta)),0.1,0.1), upper=rep(Inf,length(start.par)),
                         mydata=d, x.col.ix.gamma=x.col.ix.gamma, x.col.ix.beta=x.col.ix.beta, hessian=T)

    wei.full.par= wei.icpv.full$par
    wei.full.sd= wei.icpv.full$hessian

### single-step: "Maziarz" backward time only, weibull baseline (see function documentation for more)
    start.par= c(pc$init.beta, pc$init.gamma)
    wei.icpv.full2= optim(start.par, fn=neg.loglik.weibull.full2, method="L-BFGS-B",
                          lower=c(rep(-Inf,length(xnames.gamma)),rep(-Inf,length(pc$init.beta)),0.1,0.1), upper=rep(Inf,length(start.par)),
                          mydata=d, x.col.ix.gamma=x.col.ix.gamma, x.col.ix.beta=x.col.ix.beta, hessian=T)
    wei.full.par2= wei.icpv.full2$par
    wei.full.sd2= wei.icpv.full2$hessian

### single-step: "Maziarz" backward time only, exponential baseline (see function documentation for more)
    start.par= c(pc$init.beta, pc$init.gamma[1:2], 1)
    wei.icpv.full3= optim(start.par, fn=neg.loglik.full3.exp, method="L-BFGS-B",
                          lower=c(rep(-Inf,length(xnames.gamma)),rep(-Inf,length(pc$init.beta)),0.1), upper=rep(Inf,length(start.par)),
                          mydata=d, x.col.ix.gamma=x.col.ix.gamma, x.col.ix.beta=x.col.ix.beta, hessian=T)
    wei.full.par3= wei.icpv.full3$par
    wei.full.sd3= wei.icpv.full3$hessian

### naive method: combining incident and prevalent cases and fitting 
### a standard logistic regression, not adjusting for survival bias

    icpvcombined= d[,'case.status']
    icpvcombined[d[,'case.status']==2]= 1
    outglm= glm(icpvcombined~x1+x2,family= binomial(link = "logit"),data=d)
    outglmbeta= as.numeric(outglm$coef)

### fitting a standard logistic regression
### to controls and incident cases only

    ic.ix= which(d[,'case.status']==1)
    con.ix= which(d[,'case.status']==0)

    conicind= d[c(con.ix,ic.ix),'case.status']
    conicx1= d[c(con.ix,ic.ix),'x1']
    conicx2= d[c(con.ix,ic.ix),'x2']

    conicdata= data.frame(cbind(conicind,conicx1,conicx2))

    outglmconic= glm(conicind~conicx1+conicx2,family= binomial(link = "logit"),data=conicdata)
    outglmbetaconic= as.numeric(outglmconic$coef)

### output
    out.comb= list(out.par,out.cox,wei.full.par,
                   wei.full.par2,wei.full.par3,outglmbeta,outglmbetaconic)
    names(out.comb)= c("Two-step EM","Two-step Cox","Joint Weibull",
                       "IPCC","IPCC-Exp","Logistic Naive","Logistic IC")

out.par.r3= round(out.par,3)
out.cox.r3= round(out.cox,3)
wei.full.par.r3= round(wei.full.par,3)
wei.full.par2.r3= round(wei.full.par2,3)
wei.full.par3.r3= round(wei.full.par3,3)
outglmbeta.r3= round(outglmbeta,3)
outglmbetaconic.r3= round(outglmbetaconic,3)

    print("Two-step EM")
    print(paste("alpha= ",out.par.r3[1],"nu= ",out.par.r3[2],"beta1= ",out.par.r3[3],"beta2= ",out.par.r3[4],
                "gamma1= ",out.par.r3[5],"gamma2= ",out.par.r3[6]))
    print("Two-step Cox")
    print(paste("alpha= ",out.cox.r3[1],"nu= ",out.cox.r3[2],"beta1= ",out.cox.r3[3],"beta2= ",out.cox.r3[4],
                "gamma1= ",out.cox.r3[5],"gamma2= ",out.cox.r3[6]))

    print("Joint Weibull")
    print(paste("alpha= ",wei.full.par.r3[1],"nu= ",wei.full.par.r3[2],"beta1= ",wei.full.par.r3[3],"beta2= ",wei.full.par.r3[4],
                "gamma1= ",wei.full.par.r3[5],"gamma2= ",wei.full.par.r3[6],"kappa1= ",wei.full.par.r3[7],"kappa2= ",wei.full.par.r3[8]))
    print("IPCC")
    print(paste("alpha= ",wei.full.par2.r3[1],"nu= ",wei.full.par2.r3[2],"beta1= ",wei.full.par2.r3[3],"beta2= ",wei.full.par2.r3[4],
                "gamma1= ",wei.full.par2.r3[5],"gamma2= ",wei.full.par2.r3[6],"kappa1= ",wei.full.par2.r3[7],"kappa2= ",wei.full.par2.r3[8]))
    print("IPCC-Exp")
    print(paste("alpha= ",wei.full.par3.r3[1],"nu= ",wei.full.par3.r3[2],"beta1= ",wei.full.par3.r3[3],"beta2= ",wei.full.par3.r3[4],
                "gamma1= ",wei.full.par3.r3[5],"gamma2= ",wei.full.par3.r3[6],"lambda-dagger= ",wei.full.par3.r3[7]))

    print("Logistic Naive")
    print(paste("intercept= ",outglmbeta.r3[1],"beta1= ",outglmbeta.r3[2],"beta2= ",outglmbeta.r3[3]))
    print("Logistic IC")
    print(paste("intercept= ",outglmbetaconic.r3[1],"beta1= ",outglmbetaconic.r3[2],"beta2= ",outglmbetaconic.r3[3]))

    return(out.comb)
}
