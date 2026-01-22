#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/config.env"
# shellcheck disable=SC1091
source "$ROOT_DIR/lib/common.sh"

PUSH_URL="${KUMA_GEMINI_PUSH:-}"
[[ -z "$PUSH_URL" ]] && exit 0

GEMINI_URL="${GEMINI_URL:-https://gemini.google.com/?hl=en}"
GEMINI_UA="${GEMINI_UA:-${UA_BROWSER:-Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.36}}"
GEMINI_LANG="${GEMINI_LANG:-en-US,en;q=0.9}"
GEMINI_COOKIE="${GEMINI_COOKIE:-}"

curl_body_and_code() {
  local url="$1"; shift
  local marker="__HTTP_CODE__:"
  local out ec last
  out="$(curl "${CURL_BASE[@]}" -A "$GEMINI_UA" "$@" -w $'\n'"$marker"'%{http_code}' "$url" 2>&1)"
  ec=$?
  last="$(printf '%s' "$out" | tail -n1)"
  if [[ "$last" == "$marker"[0-9][0-9][0-9] ]]; then
    CURL_CODE="${last#$marker}"
    CURL_BODY="$(printf '%s' "$out" | sed '$d')"
  else
    CURL_CODE=""
    CURL_BODY="$out"
  fi
  CURL_EC=$ec
}

support_gemini() {
  local loc="$1"
  local support_list=(
    AX AL DZ AS AD AO AI AQ AG AR AM AW AU AT AZ BH BD BB BE BZ BJ BM BT BO BA BW BR IO VG BN BG
    BF BI CV KH CM CA BQ KY CF TD CL CX CC CO KM CK CR CI HR CW CZ CD DK DJ DM DO EC EG SV GQ ER
    EE SZ ET FK FO FJ FI FR GF PF TF GA GE DE GH GI GR GL GD GP GU GT GG GN GW GY HT HM HN HU IS
    IN ID IQ IE IM IL IT JM JP JE JO KZ KE KI XK KW KG LA LV LB LS LR LY LI LT LU MG MW MY MV ML
    MT MH MQ MR MU YT MX FM MD MC MN ME MS MA MZ MM NA NR NP NL NC NZ NI NE NG NU NF MK MP NO OM
    PK PW PS PA PG PY PE PH PN PL PT PR QA CY CG RE RO RW BL SH KN LC MF PM VC WS SM ST SA SN RS
    SC SL SG SX SK SI SB SO ZA GS KR SS ES LK SD SR SJ SE CH TW TJ TZ TH BS GM TL TG TK TO TT TN
    TR TM TC TV VI UG UA AE GB US UM UY UZ VU VA VE VN WF EH YE ZM ZW
  )
  local item
  for item in "${support_list[@]}"; do
    if [[ "$loc" == "$item" ]]; then
      return 0
    fi
  done
  return 1
}

extract_region() {
  local body="$1"
  printf '%s' "$body" | grep -oE ',2,1,200,"[A-Z]{3}"' | head -n1 | sed -E 's/.*"([A-Z]{3})".*/\1/'
}

three_to_two() {
  local code="$1"
  if ! command -v python3 >/dev/null 2>&1; then
    printf ''
    return 1
  fi
  python3 - "$code" <<'PY'
import sys
code = sys.argv[1].upper()
mapping = {
    "ABW": "AW", "AFG": "AF", "AGO": "AO", "AIA": "AI", "ALA": "AX", "ALB": "AL", "AND": "AD",
    "ARE": "AE", "ARG": "AR", "ARM": "AM", "ASM": "AS", "ATA": "AQ", "ATF": "TF", "ATG": "AG",
    "AUS": "AU", "AUT": "AT", "AZE": "AZ", "BDI": "BI", "BEL": "BE", "BEN": "BJ", "BES": "BQ",
    "BFA": "BF", "BGD": "BD", "BGR": "BG", "BHR": "BH", "BHS": "BS", "BIH": "BA", "BLM": "BL",
    "BLR": "BY", "BLZ": "BZ", "BMU": "BM", "BOL": "BO", "BRA": "BR", "BRB": "BB", "BRN": "BN",
    "BTN": "BT", "BVT": "BV", "BWA": "BW", "CAF": "CF", "CAN": "CA", "CCK": "CC", "CHE": "CH",
    "CHL": "CL", "CHN": "CN", "CIV": "CI", "CMR": "CM", "COD": "CD", "COG": "CG", "COK": "CK",
    "COL": "CO", "COM": "KM", "CPV": "CV", "CRI": "CR", "CUB": "CU", "CUW": "CW", "CXR": "CX",
    "CYM": "KY", "CYP": "CY", "CZE": "CZ", "DEU": "DE", "DJI": "DJ", "DMA": "DM", "DNK": "DK",
    "DOM": "DO", "DZA": "DZ", "ECU": "EC", "EGY": "EG", "ERI": "ER", "ESH": "EH", "ESP": "ES",
    "EST": "EE", "ETH": "ET", "FIN": "FI", "FJI": "FJ", "FLK": "FK", "FRA": "FR", "FRO": "FO",
    "FSM": "FM", "GAB": "GA", "GBR": "GB", "GEO": "GE", "GGY": "GG", "GHA": "GH", "GIB": "GI",
    "GIN": "GN", "GLP": "GP", "GMB": "GM", "GNB": "GW", "GNQ": "GQ", "GRC": "GR", "GRD": "GD",
    "GRL": "GL", "GTM": "GT", "GUF": "GF", "GUM": "GU", "GUY": "GY", "HKG": "HK", "HMD": "HM",
    "HND": "HN", "HRV": "HR", "HTI": "HT", "HUN": "HU", "IDN": "ID", "IMN": "IM", "IND": "IN",
    "IOT": "IO", "IRL": "IE", "IRN": "IR", "IRQ": "IQ", "ISL": "IS", "ISR": "IL", "ITA": "IT",
    "JAM": "JM", "JEY": "JE", "JOR": "JO", "JPN": "JP", "KAZ": "KZ", "KEN": "KE", "KGZ": "KG",
    "KHM": "KH", "KIR": "KI", "KNA": "KN", "KOR": "KR", "KWT": "KW", "LAO": "LA", "LBN": "LB",
    "LBR": "LR", "LBY": "LY", "LCA": "LC", "LIE": "LI", "LKA": "LK", "LSO": "LS", "LTU": "LT",
    "LUX": "LU", "LVA": "LV", "MAC": "MO", "MAF": "MF", "MAR": "MA", "MCO": "MC", "MDA": "MD",
    "MDG": "MG", "MDV": "MV", "MEX": "MX", "MHL": "MH", "MKD": "MK", "MLI": "ML", "MLT": "MT",
    "MMR": "MM", "MNE": "ME", "MNG": "MN", "MNP": "MP", "MOZ": "MZ", "MRT": "MR", "MSR": "MS",
    "MTQ": "MQ", "MUS": "MU", "MWI": "MW", "MYS": "MY", "MYT": "YT", "NAM": "NA", "NCL": "NC",
    "NER": "NE", "NFK": "NF", "NGA": "NG", "NIC": "NI", "NIU": "NU", "NLD": "NL", "NOR": "NO",
    "NPL": "NP", "NRU": "NR", "NZL": "NZ", "OMN": "OM", "PAK": "PK", "PAN": "PA", "PCN": "PN",
    "PER": "PE", "PHL": "PH", "PLW": "PW", "PNG": "PG", "POL": "PL", "PRI": "PR", "PRK": "KP",
    "PRT": "PT", "PRY": "PY", "PSE": "PS", "PYF": "PF", "QAT": "QA", "REU": "RE", "ROU": "RO",
    "RUS": "RU", "RWA": "RW", "SAU": "SA", "SDN": "SD", "SEN": "SN", "SGP": "SG", "SGS": "GS",
    "SHN": "SH", "SJM": "SJ", "SLB": "SB", "SLE": "SL", "SLV": "SV", "SMR": "SM", "SOM": "SO",
    "SPM": "PM", "SRB": "RS", "SSD": "SS", "STP": "ST", "SUR": "SR", "SVK": "SK", "SVN": "SI",
    "SWE": "SE", "SWZ": "SZ", "SXM": "SX", "SYC": "SC", "SYR": "SY", "TCA": "TC", "TCD": "TD",
    "TGO": "TG", "THA": "TH", "TJK": "TJ", "TKL": "TK", "TKM": "TM", "TLS": "TL", "TON": "TO",
    "TTO": "TT", "TUN": "TN", "TUR": "TR", "TUV": "TV", "TWN": "TW", "TZA": "TZ", "UGA": "UG",
    "UKR": "UA", "UMI": "UM", "URY": "UY", "USA": "US", "UZB": "UZ", "VAT": "VA", "VCT": "VC",
    "VEN": "VE", "VGB": "VG", "VIR": "VI", "VNM": "VN", "VUT": "VU", "WLF": "WF", "WSM": "WS",
    "YEM": "YE", "ZAF": "ZA", "ZMB": "ZM", "ZWE": "ZW",
}
print(mapping.get(code, ""))
PY
}

start="$(ms_now)"

headers=( -H "Accept-Language: $GEMINI_LANG" )
if [[ -n "$GEMINI_COOKIE" ]]; then
  headers+=( -H "Cookie: $GEMINI_COOKIE" )
fi

curl_body_and_code "$GEMINI_URL" "${headers[@]}"
ec=$CURL_EC
code=$CURL_CODE
body=$CURL_BODY
ping="$(elapsed_ms "$start")"

status="down"
msg="Google Gemini: Failed"

if [[ $ec -ne 0 ]]; then
  msg="Google Gemini: Failed (Network)"
elif [[ "$code" == "403" ]]; then
  msg="Google Gemini: Banned"
elif [[ "$code" == "302" ]]; then
  msg="Google Gemini: Failed"
else
  region_three="$(extract_region "$body")"
  region_two="$(three_to_two "$region_three")"
  if [[ -n "$region_two" ]]; then
    region_uc="$(printf '%s' "$region_two" | tr '[:lower:]' '[:upper:]')"
    if support_gemini "$region_uc"; then
      status="up"
      msg="Google Gemini: Yes (Region: $region_uc)"
    else
      msg="Google Gemini: No (Region: $region_uc)"
    fi
  fi
fi

push_kuma "$PUSH_URL" "$status" "$msg" "$ping"
