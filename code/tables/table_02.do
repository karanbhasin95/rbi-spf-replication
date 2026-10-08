version 19.0
clear all
set more off

* Locate the replication root from common starting directories.
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
local output "`root'/results/tables/table02.csv"
capture mkdir "`root'/results"
capture mkdir "`root'/results/tables"

use "`data'", clear
keep if record_type == "spf_histogram"
keep survey_date survey_year survey_month growth_bin_midpoint ///
    growth_nowcast_probability growth_yearahead_probability

* Derive the point forecasts from the histogram bins.
gen double growth_nowcast_component = ///
    growth_bin_midpoint * growth_nowcast_probability
gen double growth_yearahead_component = ///
    growth_bin_midpoint * growth_yearahead_probability
collapse (sum) growth_nowcast_component growth_yearahead_component ///
    growth_nowcast_probability growth_yearahead_probability, ///
    by(survey_date survey_year survey_month)
replace growth_nowcast_component = . if growth_nowcast_probability == 0
replace growth_yearahead_component = . if growth_yearahead_probability == 0
gen byte calendar_quarter = quarter(survey_date)

tempfile survey_means nowcast_horizons yearahead_horizons source results
save "`survey_means'", replace

* Nowcast horizons: survey-quarter averages for h=4,3,2.
keep if inrange(calendar_quarter, 2, 4)
gen byte horizon = 6 - calendar_quarter
collapse (mean) growth_forecast=growth_nowcast_component, ///
    by(survey_year horizon)
save "`nowcast_horizons'", replace

* Year-ahead horizons: survey-quarter averages for h=8,7,6,5.
use "`survey_means'", clear
gen byte horizon = cond(calendar_quarter == 1, 5, 10 - calendar_quarter)
collapse (mean) growth_forecast=growth_yearahead_component, ///
    by(survey_year horizon)
keep if inrange(horizon, 5, 8)

* The March 2013 survey contains no year-ahead density.  The archived analysis
* carries the adjacent h=6 forecast into this single missing h=5 cell.
quietly summarize growth_forecast if survey_year == 2013 & horizon == 6, meanonly
replace growth_forecast = r(mean) if survey_year == 2013 & horizon == 5 ///
    & missing(growth_forecast)

append using "`nowcast_horizons'"
keep if inrange(survey_year, 2008, 2022)
gsort survey_year -horizon
gen int id = _n
gen double growth_fcast_rev = growth_forecast - growth_forecast[_n-1]
gen double lagged_revision = growth_fcast_rev[_n-1]
gen str3 horizon_growth = "h" + string(horizon)
order id survey_year horizon horizon_growth growth_forecast ///
    growth_fcast_rev lagged_revision
save "`source'", replace

tempname handle
postfile `handle' str24 sample str28 term double coefficient robust_standard_error ///
    int n double r_squared using "`results'", replace

quietly regress growth_fcast_rev lagged_revision, vce(robust)
post `handle' ("Dec 2007-Jan 2023") ("Lagged Forecast Revision") ///
    (_b[lagged_revision]) (_se[lagged_revision]) (e(N)) (e(r2))
post `handle' ("Dec 2007-Jan 2023") ("Constant") ///
    (_b[_cons]) (_se[_cons]) (e(N)) (e(r2))

use "`source'", clear
keep if id < 88
quietly regress growth_fcast_rev lagged_revision, vce(robust)
post `handle' ("Dec 2007-Jan 2020") ("Lagged Forecast Revision") ///
    (_b[lagged_revision]) (_se[lagged_revision]) (e(N)) (e(r2))
post `handle' ("Dec 2007-Jan 2020") ("Constant") ///
    (_b[_cons]) (_se[_cons]) (e(N)) (e(r2))

postclose `handle'
use "`results'", clear
export delimited using "`output'", replace
