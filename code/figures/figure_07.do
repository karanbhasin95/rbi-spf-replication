version 19.0
clear all
set more off


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
local irf_file "`root'/.figure07_runtime"
global REPRO_FIG_OUT "`out'"
capture mkdir "`root'/results"
capture mkdir "`out'"
set scheme s2color
graph set window fontface "Times New Roman"

program define plot_figure07_irf
    syntax, Response(string) File(string) Title(string)
    twoway (line irf_coirf irf_horizon if irf_response=="`response'" & ///
                irf_model=="SVAR (7) SPF Uncertainty Shock", ///
                lcolor(black) lwidth(thick)) ///
           (line irf_coirf irf_horizon if irf_response=="`response'" & ///
                irf_model=="SVAR (6) SPF Uncertainty Shock", ///
                lcolor(gs8) lpattern(dash) lwidth(thick)), ///
           title("`title'", size(medsmall) color(black)) ///
           xlabel(0(1)10, labsize(small)) xtitle("") ytitle("") ///
           ylabel(, angle(horizontal) labsize(small) grid ///
               glpattern(dot) glcolor(gs13)) ///
           yline(0, lcolor(gs12)) graphregion(color(white)) ///
           plotregion(color(white)) ///
           legend(order(1 "SVAR (7) SPF Uncertainty Shock" ///
                        2 "SVAR (6) SPF Uncertainty Shock") ///
                  rows(2) size(small) region(lstyle(none)))
    graph export "$REPRO_FIG_OUT/`file'", replace width(1800)
end

use "`data'", clear
keep if record_type == "svar_model_input"
keep qdate svar_real_gdp svar_real_gfcf svar_cpi ///
    svar_spf_uncertainty svar_policy_rate svar_exchange_rate svar_cboe_vix
isid qdate
sort qdate


drop if missing(svar_real_gdp) & missing(svar_real_gfcf) & ///
    missing(svar_cpi) & missing(svar_spf_uncertainty) & ///
    missing(svar_policy_rate) & missing(svar_exchange_rate) & ///
    missing(svar_cboe_vix)
sort qdate

gen double yr_gdp = 100*ln(svar_real_gdp/svar_real_gdp[_n-4])
gen double yr_gfcf = 100*ln(svar_real_gfcf/svar_real_gfcf[_n-4])
gen double ycpi = 100*ln(svar_cpi/svar_cpi[_n-4])
gen double ysd_beta_fit_growth_ncast = ///
    100*ln(svar_spf_uncertainty/svar_spf_uncertainty[_n-1])
gen double ypolicy_rate = ///
    100*ln(svar_policy_rate/svar_policy_rate[_n-1])
gen double yexchange_rate = ///
    100*ln(svar_exchange_rate/svar_exchange_rate[_n-1])
gen double ycboe_vix = 100*ln(svar_cboe_vix/svar_cboe_vix[_n-1])

tsset qdate, quarterly

local core yr_gdp yr_gfcf ycpi ysd_beta_fit_growth_ncast ///
    ypolicy_rate yexchange_rate


matrix A6 = (1,0,0,0,0,0\.,1,0,0,0,0\.,.,1,0,0,0\ ///
    .,.,.,1,0,0\.,.,.,.,1,0\.,.,.,.,.,1)
matrix B6 = (.,0,0,0,0,0\0,.,0,0,0,0\0,0,.,0,0,0\ ///
    0,0,0,.,0,0\0,0,0,0,.,0\0,0,0,0,0,.)

matrix A7 = (1,0,0,0,0,0,0\.,1,0,0,0,0,0\.,.,1,0,0,0,0\ ///
    .,.,.,1,0,0,0\.,.,.,.,1,0,0\.,.,.,.,.,1,0\.,.,.,.,.,.,1)
matrix B7 = (.,0,0,0,0,0,0\0,.,0,0,0,0,0\0,0,.,0,0,0,0\ ///
    0,0,0,.,0,0,0\0,0,0,0,.,0,0\0,0,0,0,0,.,0\0,0,0,0,0,0,.)

irf set "`irf_file'", replace

quietly svar `core', lags(1/1) aeq(A6) beq(B6)
estimates store figure07_svar6
display as result "FIGURE07_SVAR6_N=" e(N)
irf create svar6, step(10) replace

quietly svar `core' ycboe_vix, lags(1/1) aeq(A7) beq(B7)
estimates store figure07_svar7
display as result "FIGURE07_SVAR7_N=" e(N)
irf create svar7, step(10) replace


use "`irf_file'.irf", clear
keep if inlist(irfname, "svar6", "svar7")
keep if impulse == "ysd_beta_fit_growth_ncast"
keep if inlist(response, "yr_gdp", "yr_gfcf", "ycpi", ///
    "ypolicy_rate", "yexchange_rate")
keep irfname step response coirf

rename step irf_horizon
rename response irf_response
rename coirf irf_coirf
gen str40 irf_model = ""
replace irf_model = "SVAR (6) SPF Uncertainty Shock" if irfname == "svar6"
replace irf_model = "SVAR (7) SPF Uncertainty Shock" if irfname == "svar7"
replace irf_response = "GDP" if irf_response == "yr_gdp"
replace irf_response = "GFCF" if irf_response == "yr_gfcf"
replace irf_response = "Inflation" if irf_response == "ycpi"
replace irf_response = "Policy Rate" if irf_response == "ypolicy_rate"
replace irf_response = "USD-INR Exchange Rate" if irf_response == "yexchange_rate"
drop irfname

assert _N == 110
isid irf_model irf_response irf_horizon
assert inrange(irf_horizon, 0, 10)
assert !missing(irf_coirf)
sort irf_response irf_model irf_horizon

plot_figure07_irf, response("GDP") file("figure07a.png") ///
    title("Cumulative Effect of 1 s.d. Uncertainty Shock on GDP")
plot_figure07_irf, response("Inflation") file("figure07b.png") ///
    title("Cumulative Effect of 1 s.d. Uncertainty Shock on Inflation")
plot_figure07_irf, response("GFCF") file("figure07c.png") ///
    title("Cumulative Effect of 1 s.d. Uncertainty Shock on GFCF")
plot_figure07_irf, response("Policy Rate") file("figure07d.png") ///
    title("Cumulative Effect of 1 s.d. Uncertainty Shock on Policy Rate")
plot_figure07_irf, response("USD-INR Exchange Rate") file("figure07e.png") ///
    title("Cumulative Effect of 1 s.d. Uncertainty Shock on USD-INR Exchange Rate")
capture erase "`irf_file'.irf"
