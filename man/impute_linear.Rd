% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/sits_imputation.R
\name{impute_linear}
\alias{impute_linear}
\title{Replace NA values by linear interpolation}
\usage{
impute_linear(data = NULL)
}
\arguments{
\item{data}{A time series vector or matrix}
}
\value{
A set of filtered time series using
                      the imputation function.
}
\description{
Remove NA by linear interpolation
}
\author{
Gilberto Camara, \email{gilberto.camara@inpe.br}
}
