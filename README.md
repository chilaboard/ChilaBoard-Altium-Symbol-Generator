# Chila board – Altium SchLib Generator

Turn a merged CSV/XLSX (part info + PINOUT table) into an Altium Designer `.SchLib`.
CSV/XLSX را به کتابخانه‌ی شماتیک آلتیوم (`.SchLib`) تبدیل کنید.

Three ways to use it / سه روش استفاده:

| | Where | Needs |
|---|---|---|
| **Web page** | `docs/index.html` (GitHub Pages) | any browser, works offline |
| **CLI** | `node cli/schlib-cli.js parts.csv` | Node.js ≥ 16 |
| **Altium script** | `altium/SchLibFromCSV.pas` | Altium Designer (creates objects through Altium's own API) |

## Input format / فرمت ورودی

```
Part Number,VALUE,Description,PARAM,PARAM2,Package,Price,Footprint
CH182D,CH182,"ETH PHY, 10/100M, RMII, QFN-20","10/100M, -40~85°C",3.3V,QFN-20,,
Pin No.,Pin Name,Type,Side
1,X0,Output,Left
2,XI,Input,Left
...
                                   <- blank line, then the next part
```

* `Type`: Input, IO, Output, OpenCollector, Passive, HiZ, OpenEmitter, Power
* `Side`: Left, Right, Top, Bottom
* Every extra column in the part row (except `Description`, `Footprint`, `Footprint Description`, `Verify`) becomes a hidden component parameter. `MANF_P#` is added automatically.
* `Footprint` (optional) adds a footprint link by name.
* Library reference ≤ 31 chars, none of `\ / : * ? " < > |`.
* Active-low pins: write `RESET#` (default) or choose the overbar style.

## Web page / صفحه‌ی وب
Enable GitHub Pages: *Settings → Pages → Branch `main`, folder `/docs`*. Rebuild after changing sources: `node build.js`.

## CLI
```
node cli/schlib-cli.js examples/CH182D.csv out.SchLib [--spacing 10] [--lenLR 30] [--lenTB 10] [--activeLow hash|overbar] [--order ccw|topdown]
```
(Units are 10 mil, like Altium's file format.) XLSX input works too.

## Altium script / اسکریپت آلتیوم
1. *File → New → Project → Script Project*, then *Add Existing to Project* → `SchLibFromCSV.pas` **and** `SchLibFromCSV.dfm` (or open `SchLibFromCSV.PrjScr`).
2. *File → Run Script… → `CreateFromCSV`*. A window opens:
   * paste a part table / pinout (comma- or Tab-separated, Excel paste works), or **Load CSV…**, or press **Demo**;
   * set pin spacing, L/R and T/B pin length, active-low style, ordering, and side placement (from the Side column, auto left/right split, or all left);
   * live preview of the selected part;
   * target: *New empty library* (created automatically) or *Open library*;
   * **Generate**.
3. Review the components in the SCH Library panel and save the library.

If the pasted text has only pin rows (no "Part Number" row), the part number / description / package / footprint fields in the window are used.

## Status / وضعیت
The `.SchLib` writer was verified structurally against an Altium 24 sample library (OLE layout, records, CLSIDs).
The Altium script was written without access to Altium; please report any error text.

## License
MIT. `vendor/` contains SheetJS `cfb` (patched: no extra stream) and `xlsx` under Apache-2.0.
