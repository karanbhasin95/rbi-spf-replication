version 19.0
clear all
set more off

* Table 5: Growth uncertainty and lagged forecast errors.

local root ""
capture confirm file "data/baseline_data.dta"
if !_rc local root "`c(pwd)'"
if "`root'" == "" {
    capture confirm file "baseline_data.dta"
    if !_rc local root "`c(pwd)'/.."
}
if "`root'" == "" {
    capture confirm file "../data/baseline_data.dta"
    if !_rc local root "`c(pwd)'/.."
}
if "`root'" == "" {
    capture confirm file "../../data/baseline_data.dta"
    if !_rc local root "`c(pwd)'/../.."
}
if "`root'" == "" {
    display as error "Could not locate data/baseline_data.dta"
    exit 601
}
local data "`root'/data/baseline_data.dta"
local output "`root'/results/tables/table05.csv"

capture mkdir "`root'/results"
capture mkdir "`root'/results/tables"

capture confirm file "`data'"
if _rc {
    display as error "Missing data/baseline_data.dta"
    exit 601
}


use "`data'", clear
keep if record_type == "spf_histogram"
keep survey_date qdate growth_bin_label growth_bin_midpoint ///
    growth_nowcast_probability
drop if growth_bin_label == "" | missing(growth_nowcast_probability)
gen double point_component = growth_bin_midpoint * growth_nowcast_probability
collapse (sum) midpoint_point_forecast=point_component, by(survey_date qdate)
collapse (mean) midpoint_point_forecast, by(qdate)
tempfile point_forecasts
save "`point_forecasts'", replace

use "`data'", clear
keep if record_type == "fitted_growth"
keep qdate growth_fitted_mean growth_uncertainty
drop if missing(qdate)
isid qdate
tempfile fitted_growth
save "`fitted_growth'", replace

use "`data'", clear
keep if record_type == "quarterly_macro"
keep qdate quarterly_real_gdp
isid qdate
tsset qdate, quarterly
gen double realized_growth = 100 * (quarterly_real_gdp / L4.quarterly_real_gdp - 1)
tempfile quarterly_macro
save "`quarterly_macro'", replace

use "`fitted_growth'", clear
merge 1:1 qdate using "`point_forecasts'", assert(match) nogen
merge 1:1 qdate using "`quarterly_macro'", keep(match) nogen
sort qdate
tsset qdate, quarterly

gen int year = year(dofq(qdate))
gen byte month = month(dofq(qdate))
gen double nowcast_error = realized_growth - midpoint_point_forecast
gen double absolute_nowcast_error = abs(nowcast_error)
gen double lag_absolute_nowcast_error = L.absolute_nowcast_error
gen double lag_uncertainty = L.growth_uncertainty
gen double forecast_revision = growth_fitted_mean - L.growth_fitted_mean
replace forecast_revision = . if month == 4
gen double positive_revision = forecast_revision if forecast_revision > 0
replace positive_revision = 0 if forecast_revision <= 0 & !missing(forecast_revision)
gen double negative_revision = forecast_revision if forecast_revision <= 0
replace negative_revision = 0 if forecast_revision > 0 & !missing(forecast_revision)

order qdate year month quarterly_real_gdp realized_growth ///
    midpoint_point_forecast growth_fitted_mean growth_uncertainty ///
    nowcast_error absolute_nowcast_error lag_absolute_nowcast_error ///
    lag_uncertainty forecast_revision positive_revision negative_revision
tempfile source results
save "`source'", replace
tempname result_handle
postfile `result_handle' str1 model str36 term double coefficient ///
    robust_standard_error int n double adjusted_r_squared ///
    str32 sample_note using "`results'", replace

quietly regress growth_uncertainty lag_absolute_nowcast_error, vce(robust)
post `result_handle' ("1") ("Forecast Errors at time t-1") ///
    (_b[lag_absolute_nowcast_error]) (_se[lag_absolute_nowcast_error]) ///
    (e(N)) (e(r2_a)) ("full retained sample")
post `result_handle' ("1") ("Constant") (_b[_cons]) (_se[_cons]) ///
    (e(N)) (e(r2_a)) ("full retained sample")

use "`source'", clear
quietly regress growth_uncertainty lag_uncertainty, vce(robust)
post `result_handle' ("2") ("Uncertainty at time t-1") ///
    (_b[lag_uncertainty]) (_se[lag_uncertainty]) ///
    (e(N)) (e(r2_a)) ("full retained sample")
post `result_handle' ("2") ("Constant") (_b[_cons]) (_se[_cons]) ///
    (e(N)) (e(r2_a)) ("full retained sample")

use "`source'", clear
quietly regress growth_uncertainty lag_absolute_nowcast_error lag_uncertainty ///
    positive_revision negative_revision if year <= 2022, vce(robust)
post `result_handle' ("3") ("Forecast Errors at time t-1") ///
    (_b[lag_absolute_nowcast_error]) (_se[lag_absolute_nowcast_error]) ///
    (e(N)) (e(r2_a)) ("year<=2022")
post `result_handle' ("3") ("Uncertainty at time t-1") ///
    (_b[lag_uncertainty]) (_se[lag_uncertainty]) ///
    (e(N)) (e(r2_a)) ("year<=2022")
post `result_handle' ("3") ("Positive Revision at time t") ///
    (_b[positive_revision]) (_se[positive_revision]) ///
    (e(N)) (e(r2_a)) ("year<=2022")
post `result_handle' ("3") ("Negative Revision at time t") ///
    (_b[negative_revision]) (_se[negative_revision]) ///
    (e(N)) (e(r2_a)) ("year<=2022")
post `result_handle' ("3") ("Constant") (_b[_cons]) (_se[_cons]) ///
    (e(N)) (e(r2_a)) ("year<=2022")

postclose `result_handle'
use "`results'", clear
export delimited using "`output'", replace

display as result "Table 5 built from retained uncertainty values and core observations."
