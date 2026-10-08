version 19.0
clear all
set more off
* Locate the package root when run from the root, data/, code/,
* code/tables/, or code/figures/. No machine-specific path is required.
local root ""
foreach candidate in "`c(pwd)'" "`c(pwd)'/.." "`c(pwd)'/../.." {
    if "`root'" == "" {
        capture confirm file "`candidate'/data/baseline_data.dta"
        if !_rc {
            capture confirm file "`candidate'/code/master.do"
            if !_rc local root "`candidate'"
        }
    }
}
if "`root'" == "" {
    display as error "Could not locate the replication package's data/baseline_data.dta."
    display as error "Change directory to the package folder containing code/ and data/, then rerun the whole do-file."
    exit 601
}
local data "`root'/data/baseline_data.dta"
local out "`root'/results/figures"
capture mkdir "`root'/results"
capture mkdir "`out'"
set scheme s1color
graph set window fontface "Times New Roman"

use "`data'", clear

preserve
    keep if record_type == "monthly_uncertainty"
    keep uncertainty_date epu_index_raw india_vix_raw
    assert _N == 186
    gen int qdate = qofd(uncertainty_date)
    format qdate %tq
    collapse (mean) epu_index_raw india_vix_raw, by(qdate)
    tempfile quarterly_markets
    save "`quarterly_markets'", replace
restore

keep if record_type == "fitted_growth"
keep qdate growth_uncertainty
isid qdate
merge 1:1 qdate using "`quarterly_markets'", keep(match) nogen

keep if inrange(qdate, tq(2008q1), tq(2023q1))
sort qdate
assert _N == 61
assert qdate[1] == tq(2008q1)
assert qdate[_N] == tq(2023q1)

quietly summarize epu_index_raw if qdate == tq(2008q1), meanonly
assert r(N) == 1
local epu_base = r(mean)
quietly summarize india_vix_raw if qdate == tq(2008q1), meanonly
assert r(N) == 1
local vix_base = r(mean)
quietly summarize growth_uncertainty if qdate == tq(2008q1), meanonly
assert r(N) == 1
local spf_base = r(mean)

gen double epu_index_2008q1_100 = 100 * epu_index_raw / `epu_base'
gen double vix_2008q1_100 = 100 * india_vix_raw / `vix_base'
gen double spf_uncertainty_2008q1_100 = 100 * growth_uncertainty / `spf_base'
assert abs(epu_index_2008q1_100 - 100) < 1e-10 if qdate == tq(2008q1)
assert abs(vix_2008q1_100 - 100) < 1e-10 if qdate == tq(2008q1)
assert abs(spf_uncertainty_2008q1_100 - 100) < 1e-10 if qdate == tq(2008q1)


gen byte recession = ///
    inrange(qdate, tq(2008q4), tq(2009q1)) | ///
    inrange(qdate, tq(2013q3), tq(2013q4)) | ///
    qdate == tq(2017q1) | ///
    inrange(qdate, tq(2020q2), tq(2021q2))
count if recession
assert r(N) == 10

gen double recession_band = 250 if recession

twoway ///
    (bar recession_band qdate if recession, barwidth(1) color(gs12) lcolor(none)) ///
    (line epu_index_2008q1_100 qdate, sort lcolor(gs8) lpattern(longdash) lwidth(medthick)) ///
    (line spf_uncertainty_2008q1_100 qdate, sort lcolor("0 32 96") lwidth(thick)) ///
    (connected vix_2008q1_100 qdate, sort lcolor(gs7) lpattern(dot) ///
        lwidth(medthick) mcolor(gs7) msymbol(triangle) msize(vsmall)), ///
    yscale(range(0 250)) ylabel(0(50)250, angle(horizontal) grid glcolor(gs14) glpattern(dot)) ///
    xlabel(`=tq(2008q1)'(2)`=tq(2023q1)', format(%tq) angle(vertical) labsize(small)) ///
    ytitle("") xtitle("") ///
    legend(order(1 "Recession" 2 "EPU Index" 3 "SPF Uncertainty" 4 "Vix") ///
        rows(1) position(6) ring(1) region(lstyle(none) fcolor(none))) ///
    graphregion(color(white)) plotregion(color(white)) xsize(14) ysize(7)

graph export "`out'/figure06.png", replace width(2200)
