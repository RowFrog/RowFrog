# Model check, 2026-10-24 17:02 UTC

5 forecast runs stored (2026-10-23T20:00Z to 2026-10-24T17:00Z).
Errors are mean absolute differences to the nearest DWD station; bias > 0 means the model is too high.
"Light wrong" = how often wind and gusts alone would have given a different rowing light than measured.
Stations are on land, where wind is usually weaker than on the lake, so the ranking matters more than the numbers.

## All points, day 1

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| ecmwf_ifs025 | 80 | 1.7 | -0.0 | 3.0 | 2.0 | 50 % |
| icon_eu | 80 | 1.7 | -0.7 | 3.4 | 1.0 | 47 % |
| ecmwf_aifs025_single | 80 | 1.9 | -1.3 | – | 1.1 | – |
| **icon_d2** (app today) | 80 | 2.0 | -0.4 | 3.3 | 0.9 | 50 % |
| best_match | 80 | 2.0 | -0.4 | 3.3 | 0.9 | 50 % |
| knmi_harmonie_arome_europe | 80 | 2.0 | -1.1 | 3.7 | 1.2 | 53 % |
| dmi_harmonie_arome_europe | 80 | 2.1 | +0.2 | 4.2 | 1.1 | 60 % |
| meteoswiss_icon_ch2 | 80 | 2.2 | +0.8 | 3.9 | 1.2 | 58 % |
| geosphere_arome_austria | 80 | 2.5 | +0.5 | 4.0 | 1.1 | 65 % |
| meteoswiss_icon_ch1 | 80 | 2.5 | +2.0 | 3.8 | 1.5 | 55 % |

## All points, archive

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 14385 | 0.8 | -0.0 | 1.7 | 1.2 | 9 % |
| **icon_d2** (app today) | 14385 | 0.9 | +0.2 | 1.6 | 1.4 | 9 % |
| best_match | 14385 | 0.9 | +0.2 | 1.6 | 1.4 | 9 % |
| ecmwf_aifs025_single | 14385 | 0.9 | +0.1 | – | 1.4 | – |
| knmi_harmonie_arome_europe | 14385 | 1.0 | +0.2 | 1.6 | 1.3 | 7 % |
| ecmwf_ifs025 | 14385 | 1.0 | +0.3 | 1.8 | 1.2 | 10 % |
| meteoswiss_icon_ch2 | 14385 | 1.0 | +0.4 | 2.0 | 1.5 | 11 % |
| dmi_harmonie_arome_europe | 14385 | 1.1 | +0.3 | 1.8 | 1.3 | 9 % |
| geosphere_arome_austria | 14385 | 1.1 | +0.4 | 1.6 | 1.7 | 9 % |
| meteoswiss_icon_ch1 | 14385 | 1.1 | +0.5 | 1.9 | 1.6 | 10 % |

## icon_d2 vs best_match

107 forecast hours differ by more than wind 2.0 m/s, gusts 3.0 m/s or air 2.0 °C.

| Point | Hours |
| --- | --- |
| starnberger-see-south | 43 |
| staffelsee | 28 |
| starnberger-see-centre | 17 |
| tegernsee | 8 |
| kochelsee | 8 |
| tutzinger-rv | 3 |

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
| ecmwf_ifs025 | 8 | 0.9 | +0.6 | 2.0 | 2.0 | 33 % |
| icon_eu | 8 | 1.1 | -0.8 | 2.1 | 0.9 | 50 % |
| knmi_harmonie_arome_europe | 8 | 1.1 | -0.9 | 2.4 | 1.3 | 17 % |
| ecmwf_aifs025_single | 8 | 1.2 | -0.9 | – | 0.9 | – |
| geosphere_arome_austria | 8 | 1.2 | +0.8 | 2.1 | 0.6 | 17 % |
| dmi_harmonie_arome_europe | 8 | 1.2 | +0.8 | 2.2 | 0.9 | 50 % |
| meteoswiss_icon_ch2 | 8 | 1.4 | +1.4 | 2.6 | 1.3 | 50 % |
| **icon_d2** (app today) | 8 | 1.6 | -0.5 | 1.8 | 0.7 | 50 % |
| best_match | 8 | 1.6 | -0.5 | 1.8 | 0.7 | 50 % |
| meteoswiss_icon_ch1 | 8 | 1.8 | +1.8 | 4.7 | 0.9 | 67 % |

### Tutzinger RV launch point

Stations: wind: Wielenbach (Demollstr.) (8.9 km), gust: Wielenbach (Demollstr.) (8.9 km), temp: Attenkam (6.9 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| ecmwf_ifs025 | 8 | 0.9 | +0.6 | 2.0 | 1.9 | 33 % |
| dmi_harmonie_arome_europe | 8 | 1.1 | -0.4 | 2.5 | 1.5 | 33 % |
| ecmwf_aifs025_single | 8 | 1.2 | -0.9 | – | 0.8 | – |
| meteoswiss_icon_ch2 | 8 | 1.3 | +0.6 | 1.8 | 1.3 | 50 % |
| icon_eu | 8 | 1.4 | -0.8 | 2.4 | 1.5 | 50 % |
| geosphere_arome_austria | 8 | 1.5 | -0.8 | 3.1 | 1.5 | 100 % |
| meteoswiss_icon_ch1 | 8 | 1.6 | +1.6 | 2.2 | 0.9 | 33 % |
| **icon_d2** (app today) | 8 | 1.6 | -1.1 | 3.1 | 1.3 | 50 % |
| best_match | 8 | 1.6 | -1.1 | 3.1 | 1.3 | 50 % |
| knmi_harmonie_arome_europe | 8 | 2.3 | -2.3 | 2.0 | 1.8 | 50 % |

### Starnberger See, centre

Stations: wind: Wielenbach (Demollstr.) (11.4 km), gust: Wielenbach (Demollstr.) (11.4 km), temp: Attenkam (5.2 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| knmi_harmonie_arome_europe | 8 | 0.8 | -0.2 | 2.2 | 0.6 | 50 % |
| ecmwf_ifs025 | 8 | 0.9 | +0.6 | 2.0 | 1.9 | 33 % |
| ecmwf_aifs025_single | 8 | 1.2 | -0.9 | – | 0.8 | – |
| icon_eu | 8 | 1.4 | -0.2 | 2.4 | 1.0 | 50 % |
| meteoswiss_icon_ch2 | 8 | 1.6 | +1.5 | 4.3 | 0.9 | 50 % |
| dmi_harmonie_arome_europe | 8 | 1.7 | +1.7 | 4.7 | 0.5 | 50 % |
| **icon_d2** (app today) | 8 | 1.9 | +0.2 | 3.9 | 0.5 | 100 % |
| best_match | 8 | 1.9 | +0.2 | 3.9 | 0.5 | 100 % |
| geosphere_arome_austria | 8 | 2.5 | +1.7 | 3.2 | 0.6 | 100 % |
| meteoswiss_icon_ch1 | 8 | 4.6 | +4.6 | 4.7 | 3.3 | 67 % |

### Starnberger See, south near Seeshaupt

Stations: wind: Wielenbach (Demollstr.) (13.6 km), gust: Wielenbach (Demollstr.) (13.6 km), temp: Attenkam (5.6 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| dmi_harmonie_arome_europe | 8 | 1.2 | -0.9 | 1.9 | 0.8 | 33 % |
| geosphere_arome_austria | 8 | 1.2 | +1.0 | 2.2 | 0.4 | 50 % |
| meteoswiss_icon_ch2 | 8 | 1.4 | +1.3 | 3.5 | 0.5 | 50 % |
| meteoswiss_icon_ch1 | 8 | 1.5 | -0.6 | 3.6 | 0.8 | 83 % |
| **icon_d2** (app today) | 8 | 1.6 | -1.3 | 3.3 | 0.9 | 50 % |
| best_match | 8 | 1.6 | -1.3 | 3.3 | 0.9 | 50 % |
| ecmwf_ifs025 | 8 | 1.7 | -1.7 | 2.7 | 2.7 | 83 % |
| icon_eu | 8 | 1.8 | -1.8 | 2.5 | 1.6 | 50 % |
| knmi_harmonie_arome_europe | 8 | 2.6 | -2.6 | 2.6 | 1.3 | 50 % |
| ecmwf_aifs025_single | 8 | 2.9 | -2.9 | – | 1.9 | – |

### Ammersee, centre

Stations: wind: Wielenbach (Demollstr.) (13.3 km), gust: Wielenbach (Demollstr.) (13.3 km), temp: Wielenbach (Demollstr.) (13.3 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| ecmwf_aifs025_single | 8 | 1.0 | -0.1 | – | 0.5 | – |
| icon_eu | 8 | 1.1 | +0.8 | 1.8 | 0.5 | 0 % |
| knmi_harmonie_arome_europe | 8 | 1.1 | +0.9 | 3.0 | 0.5 | 33 % |
| ecmwf_ifs025 | 8 | 1.3 | +1.3 | 2.7 | 1.8 | 33 % |
| **icon_d2** (app today) | 8 | 1.6 | +0.8 | 2.0 | 0.6 | 33 % |
| best_match | 8 | 1.6 | +0.8 | 2.0 | 0.6 | 33 % |
| meteoswiss_icon_ch2 | 8 | 1.9 | +1.7 | 4.6 | 1.1 | 50 % |
| dmi_harmonie_arome_europe | 8 | 1.9 | +1.5 | 6.3 | 0.6 | 67 % |
| geosphere_arome_austria | 8 | 3.1 | +3.1 | 3.3 | 0.5 | 67 % |
| meteoswiss_icon_ch1 | 8 | 4.9 | +4.9 | 5.0 | 3.8 | 67 % |

### Wörthsee, centre

Stations: wind: Wielenbach (Demollstr.) (20.6 km), gust: Wielenbach (Demollstr.) (20.6 km), temp: Maisach-Galgen (15.7 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| ecmwf_ifs025 | 8 | 0.9 | +0.6 | 2.0 | 1.6 | 33 % |
| knmi_harmonie_arome_europe | 8 | 1.0 | +0.1 | 2.8 | 0.9 | 50 % |
| icon_eu | 8 | 1.0 | +0.6 | 2.5 | 0.3 | 17 % |
| ecmwf_aifs025_single | 8 | 1.2 | -0.9 | – | 0.5 | – |
| **icon_d2** (app today) | 8 | 1.6 | +1.0 | 2.2 | 0.2 | 33 % |
| best_match | 8 | 1.6 | +1.0 | 2.2 | 0.2 | 33 % |
| meteoswiss_icon_ch1 | 8 | 1.7 | +1.7 | 4.0 | 0.6 | 50 % |
| meteoswiss_icon_ch2 | 8 | 1.8 | +1.8 | 3.6 | 1.2 | 67 % |
| geosphere_arome_austria | 8 | 2.2 | +1.9 | 4.6 | 0.6 | 67 % |
| dmi_harmonie_arome_europe | 8 | 2.7 | +2.7 | 4.5 | 0.7 | 67 % |

### Tegernsee, centre

Stations: wind: Kreuth (9.0 km), gust: Bichl (25.7 km), temp: Kreuth (9.0 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| ecmwf_aifs025_single | 8 | 1.4 | +1.4 | – | 1.6 | – |
| icon_eu | 8 | 1.9 | +1.8 | 4.5 | 1.4 | 50 % |
| knmi_harmonie_arome_europe | 8 | 2.0 | +2.0 | 2.9 | 1.6 | 67 % |
| ecmwf_ifs025 | 8 | 2.3 | +2.3 | 2.4 | 2.8 | 50 % |
| geosphere_arome_austria | 8 | 2.3 | +2.3 | 3.6 | 3.6 | 50 % |
| **icon_d2** (app today) | 8 | 2.7 | +2.7 | 4.9 | 1.4 | 50 % |
| best_match | 8 | 2.7 | +2.7 | 4.9 | 1.4 | 50 % |
| dmi_harmonie_arome_europe | 8 | 3.4 | +3.4 | 3.7 | 1.8 | 67 % |
| meteoswiss_icon_ch1 | 8 | 4.7 | +4.7 | 8.6 | 2.2 | 100 % |
| meteoswiss_icon_ch2 | 8 | 4.9 | +4.9 | 8.2 | 2.5 | 100 % |

### Kochelsee, centre

Stations: wind: Bichl (8.9 km), gust: Bichl (8.9 km), temp: Bichl (8.9 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| knmi_harmonie_arome_europe | 8 | 1.3 | -0.5 | 4.7 | 1.5 | 67 % |
| ecmwf_aifs025_single | 8 | 1.3 | -0.2 | – | 0.9 | – |
| **icon_d2** (app today) | 8 | 1.3 | -0.9 | 3.2 | 1.1 | 67 % |
| best_match | 8 | 1.3 | -0.9 | 3.2 | 1.1 | 67 % |
| icon_eu | 8 | 1.5 | -0.2 | 2.3 | 0.8 | 50 % |
| ecmwf_ifs025 | 8 | 1.5 | +1.0 | 2.2 | 1.8 | 50 % |
| dmi_harmonie_arome_europe | 8 | 1.7 | -1.0 | 5.1 | 1.6 | 83 % |
| meteoswiss_icon_ch1 | 8 | 2.0 | +0.2 | 2.1 | 0.9 | 50 % |
| meteoswiss_icon_ch2 | 8 | 2.4 | -1.3 | 3.8 | 0.6 | 67 % |
| geosphere_arome_austria | 8 | 2.6 | -1.1 | 5.7 | 1.3 | 50 % |

### Staffelsee, centre

Stations: wind: Hohenpeißenberg (16.9 km), gust: Hohenpeißenberg (16.9 km), temp: Kohlgrub, Bad (Rosshof) (7.4 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| meteoswiss_icon_ch1 | 8 | 0.6 | -0.3 | 1.2 | 0.6 | 0 % |
| meteoswiss_icon_ch2 | 8 | 4.0 | -3.9 | 5.1 | 0.6 | 33 % |
| **icon_d2** (app today) | 8 | 4.9 | -4.9 | 8.4 | 0.8 | 67 % |
| best_match | 8 | 4.9 | -4.9 | 8.4 | 0.8 | 67 % |
| icon_eu | 8 | 5.6 | -5.6 | 11.3 | 0.8 | 100 % |
| dmi_harmonie_arome_europe | 8 | 5.6 | -5.6 | 9.9 | 1.2 | 100 % |
| ecmwf_ifs025 | 8 | 5.8 | -5.8 | 11.1 | 2.1 | 100 % |
| geosphere_arome_austria | 8 | 6.1 | -6.1 | 10.6 | 0.8 | 100 % |
| ecmwf_aifs025_single | 8 | 7.0 | -7.0 | – | 1.2 | – |
| knmi_harmonie_arome_europe | 8 | 7.5 | -7.5 | 12.9 | 0.9 | 100 % |

### Olympic regatta course Oberschleißheim

Stations: wind: München-Stadt (9.2 km), gust: München-Stadt (9.2 km), temp: München-Stadt (9.2 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| knmi_harmonie_arome_europe | 8 | 0.5 | +0.2 | 1.6 | 1.3 | 50 % |
| dmi_harmonie_arome_europe | 8 | 0.5 | +0.3 | 1.8 | 1.7 | 50 % |
| **icon_d2** (app today) | 8 | 0.6 | -0.1 | 0.8 | 1.4 | 0 % |
| best_match | 8 | 0.6 | -0.1 | 0.8 | 1.4 | 0 % |
| icon_eu | 8 | 0.7 | -0.6 | 2.3 | 1.3 | 50 % |
| ecmwf_ifs025 | 8 | 0.9 | +0.5 | 1.3 | 1.7 | 50 % |
| meteoswiss_icon_ch2 | 8 | 1.1 | +0.3 | 1.8 | 1.9 | 67 % |
| ecmwf_aifs025_single | 8 | 1.1 | -0.6 | – | 1.4 | – |
| meteoswiss_icon_ch1 | 8 | 1.5 | +1.5 | 1.9 | 0.9 | 33 % |
| geosphere_arome_austria | 8 | 1.9 | +1.9 | 1.5 | 1.6 | 50 % |

Data: Open-Meteo; measurements Deutscher Wetterdienst (CC BY 4.0).
