% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/sits_plot.R
\name{plot.rfor_model}
\alias{plot.rfor_model}
\title{Plot Random Forest  model}
\usage{
\method{plot}{rfor_model}(x, y, ...)
}
\arguments{
\item{x}{Object of class "rf_model".}

\item{y}{Ignored.}

\item{...}{Further specifications for \link{plot}.}
}
\value{
A random forest object.
}
\description{
Plots the important variables in a random forest model.
}
\note{
Please refer to the sits documentation available in
<https://e-sensing.github.io/sitsbook/> for detailed examples.
}
\examples{
if (sits_run_examples()) {
    # Retrieve the samples for Mato Grosso
    # train a random forest model
    rf_model <- sits_train(samples_modis_ndvi,  ml_method = sits_rfor())
    # plot the model
    plot(rf_model)
}
}
\author{
Gilberto Camara, \email{gilberto.camara@inpe.br}
}
