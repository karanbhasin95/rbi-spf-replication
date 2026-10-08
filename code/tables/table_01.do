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
local output "`root'/results/tables/table01.csv"
capture mkdir "`root'/results"
capture mkdir "`root'/results/tables"

use "`data'", clear
keep if record_type == "annual_gdp"
keep annual_year annual_real_gdp
rename annual_year year
sort year
gen double real_gdp_growth = 100 * (annual_real_gdp / annual_real_gdp[_n-1] - 1)
drop annual_real_gdp
tempfile results
tempname handle
postfile `handle' str12 period int start_year int end_year_used int n ///
    double mean standard_deviation using "`results'", replace
quietly summarize real_gdp_growth if inrange(year,1950,1979)
post `handle' ("1950-79") (1950) (1979) (r(N)) (r(mean)) (r(sd))
quietly summarize real_gdp_growth if inrange(year,1980,1989)
post `handle' ("1980-89") (1980) (1989) (r(N)) (r(mean)) (r(sd))
quietly summarize real_gdp_growth if inrange(year,1990,1999)
post `handle' ("1990-99") (1990) (1999) (r(N)) (r(mean)) (r(sd))
quietly summarize real_gdp_growth if inrange(year,2000,2009)
post `handle' ("2000-09") (2000) (2009) (r(N)) (r(mean)) (r(sd))
quietly summarize real_gdp_growth if inrange(year,2010,2019)
post `handle' ("2010-19") (2010) (2019) (r(N)) (r(mean)) (r(sd))
quietly summarize real_gdp_growth if inrange(year,2010,2022)
post `handle' ("2010-22") (2010) (2022) (r(N)) (r(mean)) (r(sd))
postclose `handle'
use "`results'", clear
export delimited using "`output'", replace
