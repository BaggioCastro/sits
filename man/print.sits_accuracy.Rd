% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/sits_accuracy.R
\name{print.sits_accuracy}
\alias{print.sits_accuracy}
\title{Print the values of a confusion matrix}
\usage{
\method{print}{sits_accuracy}(x, ..., digits = max(3, getOption("digits") - 3))
}
\arguments{
\item{x}{Object of class \code{confusionMatrix}.}

\item{\dots}{Other parameters passed to the "print" function.}

\item{digits}{Number of significant digits when printed.}
}
\value{
No return value, called for side effects.
}
\description{
Adaptation of the caret::print.confusionMatrix method
             for the more common usage in Earth Observation.
}
\author{
Gilberto Camara, \email{gilberto.camara@inpe.br}
}
\keyword{internal}
