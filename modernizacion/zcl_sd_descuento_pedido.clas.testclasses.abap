*"* use this source file for your ABAP unit test classes
CLASS ltc_descuento DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    DATA mo_cut TYPE REF TO zcl_sd_descuento_pedido.

    METHODS setup.
    METHODS calcular
      IMPORTING iv_auart            TYPE vbak-auart
                iv_kunnr            TYPE vbak-kunnr DEFAULT '0000002000'
                iv_waerk            TYPE vbak-waerk
                iv_total            TYPE vbak-netwr
      RETURNING VALUE(rv_descuento) TYPE vbak-netwr.

    " Caracterización: T-01..T-04 del documento de entendimiento
    METHODS t01_zor_mxn_mayor_100k       FOR TESTING.
    METHODS t02_zor_usd_cliente_pref     FOR TESTING.
    METHODS t03_devolucion_aumenta_neto  FOR TESTING.
    METHODS t04_tipo_no_listado_sin_desc FOR TESTING.

    " Resto de ramas del árbol de decisión
    METHODS zor_usd_mayor_100k           FOR TESTING.
    METHODS zor_otra_moneda_mayor_100k   FOR TESTING.
    METHODS ta_mxn_entre_50k_y_100k      FOR TESTING.
    METHODS zor2_usd_entre_50k_y_100k    FOR TESTING.
    METHODS zor_menor_igual_50k          FOR TESTING.

    " Límites estrictos (>) heredados del legacy
    METHODS limite_exacto_100k_no_es_alto  FOR TESTING.
    METHODS limite_exacto_50k_sin_desc     FOR TESTING.

    " es_descuento_alto
    METHODS desc_alto_15_porciento       FOR TESTING.
    METHODS desc_alto_exacto_12_no_alto  FOR TESTING.
    METHODS desc_alto_total_cero         FOR TESTING.
ENDCLASS.


CLASS ltc_descuento IMPLEMENTATION.

  METHOD setup.
    mo_cut = NEW #( ).
  ENDMETHOD.

  METHOD calcular.
    rv_descuento = mo_cut->calcular( iv_auart = iv_auart
                                     iv_kunnr = iv_kunnr
                                     iv_waerk = iv_waerk
                                     iv_total = iv_total ).
  ENDMETHOD.

  METHOD t01_zor_mxn_mayor_100k.
    cl_abap_unit_assert=>assert_equals(
      exp = CONV vbak-netwr( '9600.00' )
      act = calcular( iv_auart = 'ZOR' iv_waerk = 'MXN' iv_total = '120000.00' ) ).
  ENDMETHOD.

  METHOD t02_zor_usd_cliente_pref.
    cl_abap_unit_assert=>assert_equals(
      exp = CONV vbak-netwr( '18000.00' )
      act = calcular( iv_auart = 'ZOR' iv_kunnr = '0000001000'
                      iv_waerk = 'USD' iv_total = '120000.00' ) ).
  ENDMETHOD.

  METHOD t03_devolucion_aumenta_neto.
    " Descuento negativo => neto = total - (-200) = total + 200
    cl_abap_unit_assert=>assert_equals(
      exp = CONV vbak-netwr( '-200.00' )
      act = calcular( iv_auart = 'ZRE' iv_waerk = 'MXN' iv_total = '10000.00' ) ).
  ENDMETHOD.

  METHOD t04_tipo_no_listado_sin_desc.
    cl_abap_unit_assert=>assert_equals(
      exp = CONV vbak-netwr( '0' )
      act = calcular( iv_auart = 'OR' iv_waerk = 'MXN' iv_total = '999999.00' ) ).
  ENDMETHOD.

  METHOD zor_usd_mayor_100k.
    cl_abap_unit_assert=>assert_equals(
      exp = CONV vbak-netwr( '12000.00' )
      act = calcular( iv_auart = 'ZOR' iv_waerk = 'USD' iv_total = '120000.00' ) ).
  ENDMETHOD.

  METHOD zor_otra_moneda_mayor_100k.
    cl_abap_unit_assert=>assert_equals(
      exp = CONV vbak-netwr( '6000.00' )
      act = calcular( iv_auart = 'ZOR' iv_waerk = 'EUR' iv_total = '120000.00' ) ).
  ENDMETHOD.

  METHOD ta_mxn_entre_50k_y_100k.
    cl_abap_unit_assert=>assert_equals(
      exp = CONV vbak-netwr( '2400.00' )
      act = calcular( iv_auart = 'TA' iv_waerk = 'MXN' iv_total = '60000.00' ) ).
  ENDMETHOD.

  METHOD zor2_usd_entre_50k_y_100k.
    cl_abap_unit_assert=>assert_equals(
      exp = CONV vbak-netwr( '1800.00' )
      act = calcular( iv_auart = 'ZOR2' iv_waerk = 'USD' iv_total = '60000.00' ) ).
  ENDMETHOD.

  METHOD zor_menor_igual_50k.
    cl_abap_unit_assert=>assert_equals(
      exp = CONV vbak-netwr( '0' )
      act = calcular( iv_auart = 'ZOR' iv_waerk = 'MXN' iv_total = '30000.00' ) ).
  ENDMETHOD.

  METHOD limite_exacto_100k_no_es_alto.
    " 100000 exacto cae en el tramo medio (4 % MXN), no en el alto (8 %)
    cl_abap_unit_assert=>assert_equals(
      exp = CONV vbak-netwr( '4000.00' )
      act = calcular( iv_auart = 'ZOR' iv_waerk = 'MXN' iv_total = '100000.00' ) ).
  ENDMETHOD.

  METHOD limite_exacto_50k_sin_desc.
    cl_abap_unit_assert=>assert_equals(
      exp = CONV vbak-netwr( '0' )
      act = calcular( iv_auart = 'ZOR' iv_waerk = 'MXN' iv_total = '50000.00' ) ).
  ENDMETHOD.

  METHOD desc_alto_15_porciento.
    cl_abap_unit_assert=>assert_true(
      mo_cut->es_descuento_alto( iv_descuento = '15000.00' iv_total = '100000.00' ) ).
  ENDMETHOD.

  METHOD desc_alto_exacto_12_no_alto.
    cl_abap_unit_assert=>assert_false(
      mo_cut->es_descuento_alto( iv_descuento = '12000.00' iv_total = '100000.00' ) ).
  ENDMETHOD.

  METHOD desc_alto_total_cero.
    cl_abap_unit_assert=>assert_false(
      mo_cut->es_descuento_alto( iv_descuento = '0' iv_total = '0' ) ).
  ENDMETHOD.

ENDCLASS.
