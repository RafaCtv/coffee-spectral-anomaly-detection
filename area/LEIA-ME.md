# Área de estudo

Polígono da fazenda em GeoJSON, EPSG:4326.

```
area/
  fazenda_car.geojson    área definitiva (referenciada no config.yml)
  candidata_01.geojson   opcional, para comparar antes de decidir
```

```bash
python gee/checa_area.py --area area/candidata_01.geojson
```

Critérios de escolha e procedimento de ajuste dos polígonos:
[`docs/escolha_da_area.md`](../docs/escolha_da_area.md).

Ao salvar o polígono definitivo, registrar o sensor e a data da imagem usada
como referência, se houve recuo da borda do talhão e quais talhões passaram por
renovação ou recepa em data conhecida.
