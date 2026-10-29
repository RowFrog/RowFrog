# Model check, 2026-10-29 05:22 UTC

24 forecast runs stored (2026-10-23T20:00Z to 2026-10-29T05:00Z).
Errors are mean absolute differences to the nearest DWD station; bias > 0 means the model is too high.
"Light wrong" = how often wind and gusts alone would have given a different rowing light than measured.
Stations are on land, where wind is usually weaker than on the lake, so the ranking matters more than the numbers.

## All points, day 1

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 5530 | 1.6 | +0.2 | 3.1 | 1.1 | 33 % |
| best_match | 5530 | 1.7 | +0.2 | 3.0 | 1.3 | 31 % |
| **icon_d2** (app today) | 5530 | 1.7 | +0.2 | 3.0 | 1.3 | 31 % |
| ecmwf_aifs025_single | 5530 | 1.8 | +0.5 | – | 1.1 | – |
| knmi_harmonie_arome_europe | 5530 | 1.9 | +0.7 | 3.1 | 1.2 | 33 % |
| dmi_harmonie_arome_europe | 5530 | 2.0 | +0.9 | 3.4 | 1.2 | 38 % |
| ecmwf_ifs025 | 5530 | 2.0 | +1.0 | 3.2 | 1.2 | 41 % |
| meteoswiss_icon_ch2 | 5530 | 2.0 | +0.9 | 3.4 | 1.5 | 35 % |
| meteoswiss_icon_ch1 | 5520 | 2.2 | +1.2 | 3.3 | 1.5 | 35 % |
| geosphere_arome_austria | 5530 | 2.2 | +1.1 | 3.2 | 1.8 | 33 % |

## All points, day 2

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 4630 | 1.1 | -0.1 | 2.2 | 1.1 | 18 % |
| best_match | 4630 | 1.2 | -0.1 | 2.2 | 1.3 | 19 % |
| **icon_d2** (app today) | 4460 | 1.2 | -0.0 | 2.2 | 1.3 | 18 % |
| ecmwf_aifs025_single | 4630 | 1.2 | +0.4 | – | 1.2 | – |
| knmi_harmonie_arome_europe | 4630 | 1.3 | +0.4 | 2.1 | 1.5 | 20 % |
| meteoswiss_icon_ch2 | 4630 | 1.3 | +0.5 | 2.2 | 1.4 | 19 % |
| dmi_harmonie_arome_europe | 4630 | 1.3 | +0.5 | 2.3 | 1.3 | 22 % |
| geosphere_arome_austria | 4630 | 1.4 | +0.4 | 2.1 | 2.4 | 17 % |
| ecmwf_ifs025 | 4630 | 1.4 | +0.6 | 2.3 | 1.2 | 28 % |
| meteoswiss_icon_ch1 | 1230 | 1.7 | +0.9 | 2.3 | 1.5 | 26 % |

## All points, archive

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 14385 | 0.8 | -0.0 | 1.7 | 1.2 | 10 % |
| **icon_d2** (app today) | 14385 | 0.9 | +0.2 | 1.6 | 1.4 | 9 % |
| best_match | 14385 | 0.9 | +0.2 | 1.6 | 1.4 | 9 % |
| ecmwf_aifs025_single | 14385 | 0.9 | +0.1 | – | 1.4 | – |
| knmi_harmonie_arome_europe | 14385 | 1.0 | +0.2 | 1.6 | 1.3 | 8 % |
| ecmwf_ifs025 | 14385 | 1.0 | +0.3 | 1.8 | 1.2 | 11 % |
| meteoswiss_icon_ch2 | 14385 | 1.0 | +0.4 | 2.0 | 1.5 | 12 % |
| dmi_harmonie_arome_europe | 14385 | 1.1 | +0.3 | 1.8 | 1.3 | 10 % |
| geosphere_arome_austria | 14385 | 1.1 | +0.4 | 1.6 | 1.7 | 10 % |
| meteoswiss_icon_ch1 | 14385 | 1.1 | +0.5 | 1.9 | 1.6 | 11 % |

## Once a day instead of twice?

Day 1 over all points, from the two scheduled runs (04:40 and 16:40 UTC) and from the 04:40 run alone.

| Model | Hours, twice | Hours, once | Wind error, twice | Wind error, once | Light wrong, twice | Light wrong, once |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 3530 | 1200 | 1.45 | 1.10 | 26 % | 19 % |
| best_match | 3530 | 1200 | 1.52 | 1.15 | 25 % | 17 % |
| icon_d2 | 3530 | 1200 | 1.52 | 1.15 | 25 % | 17 % |
| ecmwf_aifs025_single | 3530 | 1200 | 1.59 | 1.22 | – | – |
| knmi_harmonie_arome_europe | 3530 | 1200 | 1.68 | 1.27 | 26 % | 17 % |
| dmi_harmonie_arome_europe | 3530 | 1200 | 1.74 | 1.32 | 30 % | 19 % |
| ecmwf_ifs025 | 3530 | 1200 | 1.76 | 1.38 | 32 % | 25 % |
| meteoswiss_icon_ch2 | 3530 | 1200 | 1.78 | 1.27 | 29 % | 19 % |
| meteoswiss_icon_ch1 | 3520 | 1190 | 1.93 | 1.41 | 29 % | 19 % |
| geosphere_arome_austria | 3530 | 1200 | 2.00 | 1.43 | 27 % | 17 % |

Same order of the models with one run a day: **no** (twice: icon_eu, best_match, icon_d2; once: icon_eu, best_match, icon_d2).

## icon_d2 vs best_match

124 forecast hours differ by more than wind 2.0 m/s, gusts 3.0 m/s or air 2.0 °C.

| Point | Hours |
| --- | --- |
| starnberger-see-south | 46 |
| staffelsee | 32 |
| starnberger-see-centre | 18 |
| tegernsee | 14 |
| kochelsee | 10 |
| tutzinger-rv | 3 |
| ammersee | 1 |

Latest:

| Run | Point | Hour | Differences |
| --- | --- | --- | --- |
| archive | staffelsee | 2026-10-03T00:00Z | temp +2.3 |
| archive | staffelsee | 2026-10-03T01:00Z | temp +2.2 |
| archive | staffelsee | 2026-10-04T00:00Z | temp -2.3 |
| archive | staffelsee | 2026-10-05T18:00Z | temp -2.1 |
| archive | staffelsee | 2026-10-07T00:00Z | temp -2.2 |
| archive | staffelsee | 2026-10-07T18:00Z | temp -2.4 |
| archive | staffelsee | 2026-10-12T18:00Z | temp -2.2 |
| archive | staffelsee | 2026-10-12T22:00Z | temp -2.2 |
| archive | staffelsee | 2026-10-13T04:00Z | temp -2.1 |
| archive | staffelsee | 2026-10-13T19:00Z | temp -2.1 |

## Per point (day 1)

### MRC 1880 launch point, Starnberg

Stations: wind: Wielenbach (Demollstr.) (19.0 km), gust: Wielenbach (Demollstr.) (19.0 km), temp: Attenkam (13.3 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| best_match | 553 | 1.4 | +1.0 | 2.0 | 1.1 | 22 % |
| **icon_d2** (app today) | 553 | 1.4 | +1.0 | 2.0 | 1.1 | 22 % |
| icon_eu | 553 | 1.4 | +1.0 | 2.9 | 1.0 | 35 % |
| knmi_harmonie_arome_europe | 553 | 1.6 | +1.2 | 2.9 | 0.9 | 31 % |
| ecmwf_aifs025_single | 553 | 1.8 | +1.5 | – | 1.0 | – |
| meteoswiss_icon_ch2 | 553 | 1.8 | +1.6 | 2.3 | 1.2 | 23 % |
| dmi_harmonie_arome_europe | 553 | 1.8 | +1.6 | 2.7 | 1.0 | 31 % |
| meteoswiss_icon_ch1 | 552 | 1.9 | +1.7 | 3.0 | 1.2 | 31 % |
| geosphere_arome_austria | 553 | 1.9 | +1.7 | 2.7 | 1.6 | 25 % |
| ecmwf_ifs025 | 553 | 2.0 | +1.8 | 3.2 | 1.0 | 42 % |

### Tutzinger RV launch point

Stations: wind: Wielenbach (Demollstr.) (8.9 km), gust: Wielenbach (Demollstr.) (8.9 km), temp: Attenkam (6.9 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| best_match | 553 | 0.9 | +0.2 | 1.5 | 1.0 | 20 % |
| **icon_d2** (app today) | 553 | 0.9 | +0.2 | 1.5 | 1.0 | 20 % |
| icon_eu | 553 | 1.1 | +0.7 | 2.0 | 1.0 | 26 % |
| geosphere_arome_austria | 553 | 1.2 | +0.5 | 2.4 | 1.7 | 27 % |
| knmi_harmonie_arome_europe | 553 | 1.2 | +0.4 | 1.9 | 1.1 | 22 % |
| meteoswiss_icon_ch2 | 553 | 1.4 | +1.1 | 2.0 | 1.4 | 21 % |
| dmi_harmonie_arome_europe | 553 | 1.4 | +0.9 | 2.7 | 0.8 | 29 % |
| meteoswiss_icon_ch1 | 552 | 1.5 | +1.2 | 2.0 | 1.2 | 24 % |
| ecmwf_aifs025_single | 553 | 1.8 | +1.5 | – | 1.0 | – |
| ecmwf_ifs025 | 553 | 2.0 | +1.8 | 3.2 | 1.0 | 42 % |

### Starnberger See, centre

Stations: wind: Wielenbach (Demollstr.) (11.4 km), gust: Wielenbach (Demollstr.) (11.4 km), temp: Attenkam (5.2 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 553 | 1.4 | +1.0 | 1.7 | 1.1 | 24 % |
| best_match | 553 | 1.4 | +1.1 | 2.1 | 1.1 | 22 % |
| **icon_d2** (app today) | 553 | 1.4 | +1.1 | 2.1 | 1.1 | 22 % |
| ecmwf_aifs025_single | 553 | 1.8 | +1.5 | – | 1.0 | – |
| meteoswiss_icon_ch2 | 553 | 1.9 | +1.8 | 3.0 | 1.5 | 32 % |
| knmi_harmonie_arome_europe | 553 | 2.0 | +1.7 | 3.1 | 1.0 | 32 % |
| ecmwf_ifs025 | 553 | 2.0 | +1.8 | 3.2 | 1.0 | 42 % |
| dmi_harmonie_arome_europe | 553 | 2.3 | +2.2 | 3.7 | 1.1 | 41 % |
| geosphere_arome_austria | 553 | 2.3 | +2.2 | 2.5 | 1.7 | 26 % |
| meteoswiss_icon_ch1 | 552 | 3.1 | +3.0 | 2.8 | 1.8 | 33 % |

### Starnberger See, south near Seeshaupt

Stations: wind: Wielenbach (Demollstr.) (13.6 km), gust: Wielenbach (Demollstr.) (13.6 km), temp: Attenkam (5.6 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| best_match | 553 | 0.9 | +0.0 | 1.6 | 1.0 | 23 % |
| **icon_d2** (app today) | 553 | 0.9 | +0.0 | 1.6 | 1.0 | 23 % |
| icon_eu | 553 | 1.0 | -0.1 | 1.8 | 1.1 | 24 % |
| knmi_harmonie_arome_europe | 553 | 1.2 | +0.3 | 2.1 | 1.0 | 22 % |
| meteoswiss_icon_ch1 | 552 | 1.3 | +0.8 | 2.0 | 1.3 | 23 % |
| dmi_harmonie_arome_europe | 553 | 1.3 | +0.7 | 2.2 | 1.0 | 25 % |
| ecmwf_aifs025_single | 553 | 1.3 | +0.3 | – | 0.9 | – |
| ecmwf_ifs025 | 553 | 1.5 | +0.8 | 2.6 | 1.2 | 36 % |
| geosphere_arome_austria | 553 | 1.8 | +1.6 | 2.0 | 2.0 | 23 % |
| meteoswiss_icon_ch2 | 553 | 1.8 | +1.7 | 2.5 | 1.8 | 31 % |

### Ammersee, centre

Stations: wind: Wielenbach (Demollstr.) (13.3 km), gust: Wielenbach (Demollstr.) (13.3 km), temp: Wielenbach (Demollstr.) (13.3 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 553 | 1.9 | +1.6 | 2.7 | 1.6 | 31 % |
| best_match | 553 | 2.0 | +1.7 | 2.4 | 1.6 | 26 % |
| **icon_d2** (app today) | 553 | 2.0 | +1.7 | 2.4 | 1.6 | 26 % |
| meteoswiss_icon_ch2 | 553 | 2.0 | +1.8 | 3.2 | 1.5 | 33 % |
| ecmwf_aifs025_single | 553 | 2.1 | +1.9 | – | 1.5 | – |
| dmi_harmonie_arome_europe | 553 | 2.3 | +2.0 | 4.9 | 1.8 | 48 % |
| ecmwf_ifs025 | 553 | 2.5 | +2.4 | 4.0 | 1.3 | 50 % |
| knmi_harmonie_arome_europe | 553 | 2.7 | +2.6 | 4.1 | 1.9 | 40 % |
| meteoswiss_icon_ch1 | 552 | 3.1 | +2.9 | 3.0 | 2.7 | 34 % |
| geosphere_arome_austria | 553 | 3.8 | +3.7 | 3.9 | 1.9 | 36 % |

### Wörthsee, centre

Stations: wind: Wielenbach (Demollstr.) (20.6 km), gust: Wielenbach (Demollstr.) (20.6 km), temp: Maisach-Galgen (15.7 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| ecmwf_aifs025_single | 553 | 1.8 | +1.5 | – | 0.7 | – |
| best_match | 553 | 1.8 | +1.5 | 2.3 | 1.1 | 26 % |
| **icon_d2** (app today) | 553 | 1.8 | +1.5 | 2.3 | 1.1 | 26 % |
| icon_eu | 553 | 1.9 | +1.6 | 3.1 | 0.9 | 35 % |
| ecmwf_ifs025 | 553 | 2.0 | +1.8 | 3.2 | 1.0 | 42 % |
| knmi_harmonie_arome_europe | 553 | 2.0 | +1.8 | 3.1 | 0.8 | 31 % |
| meteoswiss_icon_ch2 | 553 | 2.2 | +2.1 | 3.2 | 0.7 | 33 % |
| geosphere_arome_austria | 553 | 2.4 | +2.2 | 3.8 | 1.1 | 34 % |
| meteoswiss_icon_ch1 | 552 | 2.4 | +2.3 | 3.4 | 0.8 | 32 % |
| dmi_harmonie_arome_europe | 553 | 2.5 | +2.4 | 3.3 | 0.8 | 36 % |

### Tegernsee, centre

Stations: wind: Kreuth (9.0 km), gust: Bichl (25.7 km), temp: Kreuth (9.0 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| ecmwf_aifs025_single | 553 | 1.2 | +1.0 | – | 1.6 | – |
| icon_eu | 553 | 1.2 | +0.8 | 5.5 | 1.0 | 50 % |
| dmi_harmonie_arome_europe | 553 | 2.2 | +2.2 | 4.6 | 1.4 | 47 % |
| knmi_harmonie_arome_europe | 553 | 2.3 | +2.2 | 4.5 | 1.2 | 46 % |
| **icon_d2** (app today) | 553 | 2.4 | +2.2 | 7.4 | 1.3 | 69 % |
| best_match | 553 | 2.4 | +2.2 | 7.4 | 1.3 | 69 % |
| ecmwf_ifs025 | 553 | 2.4 | +2.2 | 3.6 | 1.8 | 43 % |
| geosphere_arome_austria | 553 | 2.5 | +2.0 | 4.1 | 2.0 | 42 % |
| meteoswiss_icon_ch2 | 553 | 2.8 | +2.7 | 7.4 | 1.3 | 71 % |
| meteoswiss_icon_ch1 | 552 | 3.1 | +2.9 | 7.8 | 1.3 | 68 % |

### Kochelsee, centre

Stations: wind: Bichl (8.9 km), gust: Bichl (8.9 km), temp: Bichl (8.9 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| ecmwf_aifs025_single | 553 | 1.0 | -0.4 | – | 1.1 | – |
| ecmwf_ifs025 | 553 | 1.1 | +0.1 | 1.9 | 1.4 | 23 % |
| knmi_harmonie_arome_europe | 553 | 1.2 | -0.1 | 2.0 | 1.2 | 24 % |
| meteoswiss_icon_ch2 | 553 | 1.2 | -0.3 | 2.3 | 1.9 | 23 % |
| best_match | 553 | 1.3 | -0.9 | 2.3 | 1.4 | 21 % |
| **icon_d2** (app today) | 553 | 1.3 | -0.9 | 2.3 | 1.4 | 21 % |
| dmi_harmonie_arome_europe | 553 | 1.3 | +0.2 | 2.3 | 1.2 | 33 % |
| geosphere_arome_austria | 553 | 1.3 | -0.3 | 2.6 | 2.2 | 31 % |
| meteoswiss_icon_ch1 | 552 | 1.4 | -0.4 | 2.4 | 1.3 | 32 % |
| icon_eu | 553 | 1.4 | -1.0 | 2.0 | 0.9 | 23 % |

### Staffelsee, centre

Stations: wind: Hohenpeißenberg (16.9 km), gust: Hohenpeißenberg (16.9 km), temp: Kohlgrub, Bad (Rosshof) (7.4 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| meteoswiss_icon_ch1 | 552 | 3.1 | -3.1 | 5.1 | 2.5 | 45 % |
| dmi_harmonie_arome_europe | 553 | 3.4 | -3.3 | 6.0 | 1.4 | 56 % |
| ecmwf_ifs025 | 553 | 3.5 | -3.5 | 5.5 | 1.1 | 57 % |
| geosphere_arome_austria | 553 | 3.6 | -3.5 | 5.9 | 2.1 | 56 % |
| knmi_harmonie_arome_europe | 553 | 3.7 | -3.6 | 6.0 | 1.3 | 53 % |
| meteoswiss_icon_ch2 | 553 | 3.7 | -3.7 | 6.2 | 2.6 | 54 % |
| ecmwf_aifs025_single | 553 | 4.0 | -4.0 | – | 1.0 | – |
| icon_eu | 553 | 4.1 | -4.1 | 7.4 | 1.5 | 61 % |
| **icon_d2** (app today) | 553 | 4.3 | -4.3 | 7.5 | 2.5 | 59 % |
| best_match | 553 | 4.3 | -4.3 | 7.5 | 2.5 | 59 % |

### Olympic regatta course Oberschleißheim

Stations: wind: München-Stadt (9.2 km), gust: München-Stadt (9.2 km), temp: München-Stadt (9.2 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 553 | 0.7 | -0.0 | 1.2 | 0.9 | 18 % |
| best_match | 553 | 0.8 | -0.0 | 1.3 | 0.9 | 22 % |
| **icon_d2** (app today) | 553 | 0.8 | -0.0 | 1.3 | 0.9 | 22 % |
| meteoswiss_icon_ch2 | 553 | 0.9 | +0.4 | 1.5 | 1.1 | 25 % |
| ecmwf_aifs025_single | 553 | 0.9 | +0.5 | – | 1.1 | – |
| knmi_harmonie_arome_europe | 553 | 0.9 | +0.4 | 1.7 | 1.1 | 27 % |
| ecmwf_ifs025 | 553 | 0.9 | +0.6 | 1.6 | 1.2 | 29 % |
| meteoswiss_icon_ch1 | 552 | 1.0 | +0.7 | 1.7 | 1.0 | 30 % |
| dmi_harmonie_arome_europe | 553 | 1.0 | +0.5 | 1.7 | 1.3 | 30 % |
| geosphere_arome_austria | 553 | 1.5 | +1.2 | 1.9 | 1.8 | 28 % |

Data: Open-Meteo; measurements Deutscher Wetterdienst (CC BY 4.0).
