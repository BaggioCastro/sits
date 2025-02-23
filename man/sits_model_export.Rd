% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/sits_model_export.R
\name{sits_model_export}
\alias{sits_model_export}
\alias{sits_model_export.sits_model}
\title{Export classification models}
\usage{
sits_model_export(ml_model)

\method{sits_model_export}{sits_model}(ml_model)
}
\arguments{
\item{ml_model}{A trained machine learning model}
}
\value{
An R object containing the model in the original format of
machine learning or deep learning package.
}
\description{
Given a trained machine learning or deep learning model,
exports the model as an object for further exploration outside the
"sits" package
}
\author{
Rolf Simoes, \email{rolf.simoes@inpe.br}

Gilberto Camara, \email{gilberto.camara@inpe.br}
}
