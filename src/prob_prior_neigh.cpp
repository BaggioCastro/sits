#include <Rcpp.h>
#include <cmath>

using namespace Rcpp;

NumericVector build_neigh(const NumericMatrix& data,
                          const IntegerMatrix& window,
                          const int& i,
                          const int& j) {

    NumericVector neigh;

    for (int k = 0; k < window.rows(); ++k) {
        for (int l = 0; l < window.cols(); ++l) {
            int data_i = i + k - window.rows() / 2, data_j = j + l - window.cols() / 2;

            if (data_i >= 0 && data_j >= 0 &&
                data_i < data.nrow() && data_j < data.ncol() && window(k, l) > 0 &&
                !std::isnan(data(data_i, data_j))) {
                neigh.push_back(data(data_i, data_j) * window(k, l));
            }
        }
    }

    return neigh;
}

double bayes_estimator_pixel(const double& p,
                              const NumericVector& neigh,
                              const double& variance) {

    if (std::isnan(p)) return NAN;
    NumericVector log_neigh = log(neigh / (10000 - neigh));
    double x = log(p / (10000.0 - p));
    double v = var(log_neigh);
    double w1 = v / (variance + v);
    double w2 = variance / (variance + v);
    double sx = w1 * x + w2 * mean(log_neigh);

    return sx;
}

// [[Rcpp::export]]
NumericVector bayes_estimator_class(const NumericMatrix& data,
                                     const IntegerMatrix& window,
                                     const double& variance) {

    int nrows = data.nrow();
    int ncols = data.ncol();

    NumericVector result(nrows * ncols);

    int k = 0;
    for (int i = 0; i < nrows; ++i) {
        for (int j = 0; j < ncols; ++j) {
            result(k++) = bayes_estimator_pixel(data(i, j), build_neigh(data, window, i, j), variance);
        }
    }

    return result;
}




