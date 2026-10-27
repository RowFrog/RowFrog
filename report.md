# Model check, 2026-10-27 05:13 UTC

20 forecast runs stored (2026-10-23T20:00Z to 2026-10-27T05:00Z).
Errors are mean absolute differences to the nearest DWD station; bias > 0 means the model is too high.
"Light wrong" = how often wind and gusts alone would have given a different rowing light than measured.
Stations are on land, where wind is usually weaker than on the lake, so the ranking matters more than the numbers.

## All points, day 1

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 4460 | 1.8 | +0.2 | 3.4 | 1.1 | 39 % |
| best_match | 4460 | 1.9 | +0.3 | 3.4 | 1.3 | 36 % |
| **icon_d2** (app today) | 4460 | 1.9 | +0.3 | 3.4 | 1.3 | 36 % |
| ecmwf_aifs025_single | 4460 | 2.0 | +0.6 | – | 1.0 | – |
| knmi_harmonie_arome_europe | 4460 | 2.1 | +0.8 | 3.5 | 1.1 | 39 % |
| dmi_harmonie_arome_europe | 4460 | 2.2 | +1.1 | 3.8 | 1.2 | 45 % |
| ecmwf_ifs025 | 4460 | 2.2 | +1.2 | 3.6 | 1.1 | 50 % |
| meteoswiss_icon_ch2 | 4460 | 2.3 | +1.1 | 3.8 | 1.5 | 41 % |
| meteoswiss_icon_ch1 | 4460 | 2.5 | +1.5 | 3.7 | 1.5 | 42 % |
| geosphere_arome_austria | 4460 | 2.5 | +1.4 | 3.5 | 1.6 | 39 % |

## All points, day 2

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 3120 | 1.3 | -0.1 | 2.4 | 1.0 | 25 % |
| ecmwf_aifs025_single | 3120 | 1.4 | +0.5 | – | 1.0 | – |
| best_match | 3120 | 1.4 | +0.1 | 2.5 | 1.3 | 24 % |
| **icon_d2** (app today) | 3020 | 1.4 | +0.1 | 2.5 | 1.3 | 24 % |
| knmi_harmonie_arome_europe | 3120 | 1.5 | +0.5 | 2.3 | 1.3 | 27 % |
| geosphere_arome_austria | 3120 | 1.5 | +0.7 | 2.3 | 1.7 | 23 % |
| meteoswiss_icon_ch2 | 3120 | 1.6 | +0.8 | 2.5 | 1.4 | 25 % |
| dmi_harmonie_arome_europe | 3120 | 1.6 | +0.7 | 2.6 | 1.2 | 31 % |
| ecmwf_ifs025 | 3120 | 1.6 | +0.8 | 2.7 | 1.0 | 40 % |
| meteoswiss_icon_ch1 | 1010 | 1.8 | +1.0 | 2.5 | 1.5 | 29 % |

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
| icon_eu | 2460 | 630 | 1.76 | 1.45 | 34 % | 32 % |
| best_match | 2460 | 630 | 1.85 | 1.51 | 31 % | 24 % |
| icon_d2 | 2460 | 630 | 1.85 | 1.52 | 31 % | 24 % |
| ecmwf_aifs025_single | 2460 | 630 | 1.88 | 1.51 | – | – |
| knmi_harmonie_arome_europe | 2460 | 630 | 1.99 | 1.56 | 35 % | 27 % |
| dmi_harmonie_arome_europe | 2460 | 630 | 2.06 | 1.66 | 40 % | 31 % |
| ecmwf_ifs025 | 2460 | 630 | 2.09 | 1.74 | 44 % | 46 % |
| meteoswiss_icon_ch2 | 2460 | 630 | 2.18 | 1.67 | 37 % | 29 % |
| meteoswiss_icon_ch1 | 2460 | 630 | 2.35 | 1.82 | 38 % | 29 % |
| geosphere_arome_austria | 2460 | 630 | 2.41 | 1.81 | 36 % | 27 % |

Same order of the models with one run a day: **no** (twice: icon_eu, best_match, icon_d2; once: icon_eu, ecmwf_aifs025_single, best_match).

## icon_d2 vs best_match

120 forecast hours differ by more than wind 2.0 m/s, gusts 3.0 m/s or air 2.0 °C.

| Point | Hours |
| --- | --- |
| starnberger-see-south | 44 |
| staffelsee | 31 |
| starnberger-see-centre | 18 |
| tegernsee | 14 |
| kochelsee | 9 |
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
| icon_eu | 446 | 1.6 | +1.2 | 3.3 | 1.1 | 42 % |
| best_match | 446 | 1.6 | +1.2 | 2.3 | 1.2 | 26 % |
| **icon_d2** (app today) | 446 | 1.6 | +1.2 | 2.3 | 1.2 | 26 % |
| knmi_harmonie_arome_europe | 446 | 1.8 | +1.3 | 3.2 | 0.9 | 38 % |
| ecmwf_aifs025_single | 446 | 2.0 | +1.7 | – | 0.9 | – |
| dmi_harmonie_arome_europe | 446 | 2.1 | +1.8 | 3.0 | 1.0 | 38 % |
| meteoswiss_icon_ch2 | 446 | 2.1 | +1.9 | 2.7 | 1.3 | 28 % |
| meteoswiss_icon_ch1 | 446 | 2.2 | +2.0 | 3.5 | 1.3 | 38 % |
| geosphere_arome_austria | 446 | 2.2 | +2.0 | 3.1 | 1.4 | 29 % |
| ecmwf_ifs025 | 446 | 2.2 | +2.1 | 3.7 | 0.8 | 52 % |

### Tutzinger RV launch point

Stations: wind: Wielenbach (Demollstr.) (8.9 km), gust: Wielenbach (Demollstr.) (8.9 km), temp: Attenkam (6.9 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| best_match | 446 | 1.0 | +0.2 | 1.7 | 1.0 | 24 % |
| **icon_d2** (app today) | 446 | 1.0 | +0.2 | 1.7 | 1.0 | 24 % |
| icon_eu | 446 | 1.3 | +0.8 | 2.3 | 1.0 | 32 % |
| geosphere_arome_austria | 446 | 1.3 | +0.6 | 2.6 | 1.6 | 33 % |
| knmi_harmonie_arome_europe | 446 | 1.3 | +0.4 | 2.1 | 1.0 | 27 % |
| dmi_harmonie_arome_europe | 446 | 1.5 | +0.9 | 2.8 | 0.9 | 35 % |
| meteoswiss_icon_ch2 | 446 | 1.6 | +1.3 | 2.2 | 1.5 | 25 % |
| meteoswiss_icon_ch1 | 446 | 1.7 | +1.4 | 2.2 | 1.2 | 29 % |
| ecmwf_aifs025_single | 446 | 2.0 | +1.7 | – | 0.9 | – |
| ecmwf_ifs025 | 446 | 2.2 | +2.1 | 3.7 | 0.8 | 52 % |

### Starnberger See, centre

Stations: wind: Wielenbach (Demollstr.) (11.4 km), gust: Wielenbach (Demollstr.) (11.4 km), temp: Attenkam (5.2 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 446 | 1.6 | +1.1 | 1.9 | 1.2 | 29 % |
| best_match | 446 | 1.6 | +1.3 | 2.4 | 1.2 | 27 % |
| **icon_d2** (app today) | 446 | 1.6 | +1.3 | 2.4 | 1.2 | 27 % |
| ecmwf_aifs025_single | 446 | 2.0 | +1.7 | – | 0.9 | – |
| knmi_harmonie_arome_europe | 446 | 2.2 | +1.9 | 3.5 | 1.1 | 39 % |
| meteoswiss_icon_ch2 | 446 | 2.2 | +2.1 | 3.5 | 1.6 | 40 % |
| ecmwf_ifs025 | 446 | 2.2 | +2.1 | 3.7 | 0.8 | 52 % |
| dmi_harmonie_arome_europe | 446 | 2.6 | +2.4 | 4.2 | 1.2 | 50 % |
| geosphere_arome_austria | 446 | 2.6 | +2.5 | 2.8 | 1.4 | 32 % |
| meteoswiss_icon_ch1 | 446 | 3.6 | +3.5 | 3.2 | 1.5 | 40 % |

### Starnberger See, south near Seeshaupt

Stations: wind: Wielenbach (Demollstr.) (13.6 km), gust: Wielenbach (Demollstr.) (13.6 km), temp: Attenkam (5.6 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| best_match | 446 | 1.0 | +0.0 | 1.7 | 1.1 | 27 % |
| **icon_d2** (app today) | 446 | 1.0 | +0.0 | 1.7 | 1.1 | 28 % |
| icon_eu | 446 | 1.1 | -0.1 | 2.0 | 1.1 | 29 % |
| knmi_harmonie_arome_europe | 446 | 1.4 | +0.3 | 2.4 | 1.0 | 27 % |
| meteoswiss_icon_ch1 | 446 | 1.4 | +0.9 | 2.2 | 1.3 | 28 % |
| dmi_harmonie_arome_europe | 446 | 1.4 | +0.7 | 2.5 | 1.0 | 30 % |
| ecmwf_aifs025_single | 446 | 1.5 | +0.3 | – | 0.9 | – |
| ecmwf_ifs025 | 446 | 1.7 | +0.9 | 3.0 | 1.0 | 44 % |
| geosphere_arome_austria | 446 | 2.1 | +1.9 | 2.2 | 1.6 | 27 % |
| meteoswiss_icon_ch2 | 446 | 2.1 | +1.9 | 2.9 | 2.0 | 38 % |

### Ammersee, centre

Stations: wind: Wielenbach (Demollstr.) (13.3 km), gust: Wielenbach (Demollstr.) (13.3 km), temp: Wielenbach (Demollstr.) (13.3 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 446 | 2.3 | +1.9 | 3.2 | 1.6 | 38 % |
| best_match | 446 | 2.3 | +2.0 | 2.6 | 1.6 | 31 % |
| **icon_d2** (app today) | 446 | 2.3 | +2.0 | 2.6 | 1.6 | 31 % |
| ecmwf_aifs025_single | 446 | 2.3 | +2.1 | – | 1.5 | – |
| meteoswiss_icon_ch2 | 446 | 2.4 | +2.2 | 3.7 | 1.5 | 40 % |
| dmi_harmonie_arome_europe | 446 | 2.6 | +2.3 | 5.6 | 1.7 | 58 % |
| ecmwf_ifs025 | 446 | 2.8 | +2.7 | 4.4 | 1.2 | 61 % |
| knmi_harmonie_arome_europe | 446 | 3.1 | +3.0 | 4.7 | 1.8 | 48 % |
| meteoswiss_icon_ch1 | 446 | 3.5 | +3.4 | 3.4 | 2.5 | 41 % |
| geosphere_arome_austria | 446 | 4.2 | +4.2 | 4.4 | 1.7 | 44 % |

### Wörthsee, centre

Stations: wind: Wielenbach (Demollstr.) (20.6 km), gust: Wielenbach (Demollstr.) (20.6 km), temp: Maisach-Galgen (15.7 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| ecmwf_aifs025_single | 446 | 2.0 | +1.7 | – | 0.7 | – |
| best_match | 446 | 2.1 | +1.8 | 2.6 | 1.1 | 31 % |
| **icon_d2** (app today) | 446 | 2.1 | +1.8 | 2.6 | 1.1 | 31 % |
| ecmwf_ifs025 | 446 | 2.2 | +2.1 | 3.7 | 0.9 | 52 % |
| icon_eu | 446 | 2.3 | +1.9 | 3.6 | 0.9 | 43 % |
| knmi_harmonie_arome_europe | 446 | 2.3 | +2.0 | 3.6 | 0.8 | 38 % |
| meteoswiss_icon_ch2 | 446 | 2.6 | +2.5 | 3.7 | 0.7 | 41 % |
| geosphere_arome_austria | 446 | 2.8 | +2.6 | 4.4 | 0.9 | 41 % |
| meteoswiss_icon_ch1 | 446 | 2.8 | +2.7 | 3.9 | 0.8 | 39 % |
| dmi_harmonie_arome_europe | 446 | 2.9 | +2.8 | 3.8 | 0.8 | 44 % |

### Tegernsee, centre

Stations: wind: Kreuth (9.0 km), gust: Bichl (25.7 km), temp: Kreuth (9.0 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| ecmwf_aifs025_single | 446 | 1.3 | +1.2 | – | 1.3 | – |
| icon_eu | 446 | 1.3 | +1.0 | 6.0 | 0.9 | 57 % |
| dmi_harmonie_arome_europe | 446 | 2.5 | +2.4 | 5.1 | 1.4 | 57 % |
| knmi_harmonie_arome_europe | 446 | 2.6 | +2.6 | 5.1 | 1.2 | 56 % |
| **icon_d2** (app today) | 446 | 2.7 | +2.6 | 8.2 | 1.2 | 76 % |
| best_match | 446 | 2.7 | +2.6 | 8.2 | 1.2 | 76 % |
| ecmwf_ifs025 | 446 | 2.7 | +2.6 | 4.0 | 1.8 | 53 % |
| geosphere_arome_austria | 446 | 2.8 | +2.5 | 4.6 | 1.8 | 52 % |
| meteoswiss_icon_ch2 | 446 | 3.3 | +3.2 | 8.2 | 1.2 | 77 % |
| meteoswiss_icon_ch1 | 446 | 3.5 | +3.5 | 8.7 | 1.2 | 77 % |

### Kochelsee, centre

Stations: wind: Bichl (8.9 km), gust: Bichl (8.9 km), temp: Bichl (8.9 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| ecmwf_ifs025 | 446 | 1.2 | +0.2 | 2.0 | 1.4 | 28 % |
| ecmwf_aifs025_single | 446 | 1.2 | -0.4 | – | 1.1 | – |
| meteoswiss_icon_ch2 | 446 | 1.3 | -0.3 | 2.5 | 2.0 | 29 % |
| knmi_harmonie_arome_europe | 446 | 1.4 | -0.0 | 2.2 | 1.2 | 30 % |
| best_match | 446 | 1.5 | -0.9 | 2.5 | 1.4 | 26 % |
| **icon_d2** (app today) | 446 | 1.5 | -0.9 | 2.5 | 1.4 | 26 % |
| geosphere_arome_austria | 446 | 1.5 | -0.2 | 2.8 | 1.9 | 39 % |
| dmi_harmonie_arome_europe | 446 | 1.5 | +0.3 | 2.5 | 1.3 | 41 % |
| meteoswiss_icon_ch1 | 446 | 1.5 | -0.4 | 2.6 | 1.3 | 39 % |
| icon_eu | 446 | 1.6 | -1.1 | 2.2 | 0.9 | 28 % |

### Staffelsee, centre

Stations: wind: Hohenpeißenberg (16.9 km), gust: Hohenpeißenberg (16.9 km), temp: Kohlgrub, Bad (Rosshof) (7.4 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| meteoswiss_icon_ch1 | 446 | 3.3 | -3.3 | 5.4 | 2.5 | 50 % |
| dmi_harmonie_arome_europe | 446 | 3.8 | -3.6 | 6.6 | 1.5 | 63 % |
| geosphere_arome_austria | 446 | 3.8 | -3.8 | 6.3 | 2.3 | 63 % |
| ecmwf_ifs025 | 446 | 3.9 | -3.8 | 5.9 | 1.1 | 64 % |
| meteoswiss_icon_ch2 | 446 | 4.1 | -4.0 | 6.6 | 2.7 | 61 % |
| knmi_harmonie_arome_europe | 446 | 4.1 | -3.9 | 6.5 | 1.4 | 59 % |
| ecmwf_aifs025_single | 446 | 4.5 | -4.5 | – | 1.0 | – |
| icon_eu | 446 | 4.5 | -4.5 | 8.1 | 1.7 | 69 % |
| **icon_d2** (app today) | 446 | 4.8 | -4.8 | 8.2 | 2.7 | 66 % |
| best_match | 446 | 4.8 | -4.8 | 8.2 | 2.7 | 67 % |

### Olympic regatta course Oberschleißheim

Stations: wind: München-Stadt (9.2 km), gust: München-Stadt (9.2 km), temp: München-Stadt (9.2 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 446 | 0.8 | +0.1 | 1.3 | 0.8 | 21 % |
| best_match | 446 | 0.8 | +0.1 | 1.4 | 0.8 | 26 % |
| **icon_d2** (app today) | 446 | 0.8 | +0.1 | 1.4 | 0.8 | 26 % |
| ecmwf_aifs025_single | 446 | 1.0 | +0.6 | – | 0.9 | – |
| meteoswiss_icon_ch2 | 446 | 1.0 | +0.6 | 1.6 | 1.0 | 29 % |
| ecmwf_ifs025 | 446 | 1.0 | +0.8 | 1.7 | 1.0 | 35 % |
| knmi_harmonie_arome_europe | 446 | 1.0 | +0.6 | 1.8 | 1.0 | 32 % |
| dmi_harmonie_arome_europe | 446 | 1.1 | +0.7 | 1.9 | 1.0 | 37 % |
| meteoswiss_icon_ch1 | 446 | 1.1 | +0.9 | 1.9 | 1.0 | 35 % |
| geosphere_arome_austria | 446 | 1.7 | +1.6 | 2.1 | 1.5 | 34 % |

Data: Open-Meteo; measurements Deutscher Wetterdienst (CC BY 4.0).
