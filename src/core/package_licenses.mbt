///|
// Open Definition registry identifiers from okfn/licenses at
// 086d0bfabce15ad0d587c7e0449c695dc0f66fcf. Only identifiers are included.
let package_license_ids : ReadOnlyArray[String] = [
  "AAL", "AFL-3.0", "AGPL-3.0", "APL-1.0", "APSL-2.0", "Against-DRM", "Apache-1.1",
  "Apache-2.0", "Artistic-2.0", "BSD-2-Clause", "BSD-3-Clause", "BSL-1.0", "BitTorrent-1.1",
  "CATOSL-1.1", "CC-BY-4.0", "CC-BY-NC-4.0", "CC-BY-NC-ND-4.0", "CC-BY-NC-SA-4.0",
  "CC-BY-ND-4.0", "CC-BY-SA-4.0", "CC0-1.0", "CDDL-1.0", "CECILL-2.1", "CNRI-Python",
  "CPAL-1.0", "CUA-OPL-1.0", "DSL", "ECL-2.0", "EFL-2.0", "EPL-1.0", "EPL-2.0", "EUDatagrid",
  "EUPL-1.1", "Entessa", "FAL-1.3", "Fair", "Frameworx-1.0", "GFDL-1.3-no-cover-texts-no-invariant-sections",
  "GPL-2.0", "GPL-3.0", "HPND", "IPA", "IPL-1.0", "ISC", "Intel", "LGPL-2.1", "LGPL-3.0",
  "LO-FR-2.0", "LPL-1.0", "LPL-1.02", "LPPL-1.3c", "MIT", "MPL-1.0", "MPL-1.1", "MPL-2.0",
  "MS-PL", "MS-RL", "MirOS", "Motosoto", "Multics", "NASA-1.3", "NCSA", "NGPL", "NPOSL-3.0",
  "NTP", "Naumen", "Nokia", "OCLC-2.0", "ODC-BY-1.0", "ODbL-1.0", "OFL-1.1", "OGL-Canada-2.0",
  "OGL-UK-1.0", "OGL-UK-2.0", "OGL-UK-3.0", "OGTSL", "OSL-3.0", "PDDL-1.0", "PHP-3.0",
  "PostgreSQL", "Python-2.0", "QPL-1.0", "RPL-1.5", "RPSL-1.0", "RSCPL", "SISSL",
  "SPL-1.0", "SimPL-2.0", "Sleepycat", "Talis", "Unlicense", "VSL-1.0", "W3C", "WXwindows",
  "Watcom-1.0", "Xnet", "ZPL-2.0", "Zlib", "dli-model-use", "geogratis", "hesa-withrights",
  "localauth-withrights", "met-office-cp", "mitre", "notspecified", "other-at", "other-closed",
  "other-nc", "other-open", "other-pd", "ukclickusepsi", "ukcrown", "ukcrown-withrights",
  "ukpsi",
]

///|
fn known_package_license(id : String) -> Bool {
  // The normative Data Package example uses this historical PDDL alias.
  id == "ODC-PDDL-1.0" || package_license_ids.contains(id)
}
