"! Cálculo del descuento de un pedido de venta.
"! Reemplaza el IF anidado (4 niveles) de FORM procesar en ZSD_PEDIDOS_LEGACY.
"! Lógica pura: no accede a base de datos, por lo que es 100% testeable.
CLASS zcl_sd_descuento_pedido DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES ty_porcentaje TYPE p LENGTH 5 DECIMALS 4.

    "! Umbral (fracción del total) a partir del cual el descuento se considera alto.
    CONSTANTS c_umbral_desc_alto TYPE ty_porcentaje VALUE '0.12'.

    "! Calcula el descuento en moneda del documento.
    "! Positivo = descuento. Negativo = recargo (devoluciones, ver nota en MODERNIZACION.md).
    "! @parameter iv_auart | Clase de documento de ventas
    "! @parameter iv_kunnr | Cliente (formato interno, 10 posiciones)
    "! @parameter iv_waerk | Moneda del documento
    "! @parameter iv_total | Suma de las posiciones, SIN conversión de moneda
    METHODS calcular
      IMPORTING iv_auart            TYPE vbak-auart
                iv_kunnr            TYPE vbak-kunnr
                iv_waerk            TYPE vbak-waerk
                iv_total            TYPE vbak-netwr
      RETURNING VALUE(rv_descuento) TYPE vbak-netwr.

    "! Indica si el descuento supera el umbral c_umbral_desc_alto del total.
    "! Protegido contra total = 0.
    METHODS es_descuento_alto
      IMPORTING iv_descuento   TYPE vbak-netwr
                iv_total       TYPE vbak-netwr
      RETURNING VALUE(rv_alto) TYPE abap_bool.

  PRIVATE SECTION.
    CONSTANTS:
      c_auart_devolucion TYPE vbak-auart VALUE 'ZRE',
      c_umbral_alto      TYPE vbak-netwr VALUE 100000,
      c_umbral_medio     TYPE vbak-netwr VALUE 50000.

    TYPES ty_auart_t  TYPE SORTED TABLE OF vbak-auart WITH UNIQUE KEY table_line.
    TYPES ty_kunnr_t  TYPE SORTED TABLE OF vbak-kunnr WITH UNIQUE KEY table_line.

    "! Tipos de documento que participan en el esquema de descuento por volumen.
    METHODS tipos_con_descuento
      RETURNING VALUE(rt_auart) TYPE ty_auart_t.

    "! Clientes con tarifa preferencial.
    "! Pendiente de pasar a tabla de customizing (ver MODERNIZACION.md).
    METHODS clientes_preferenciales
      RETURNING VALUE(rt_kunnr) TYPE ty_kunnr_t.

    METHODS porcentaje_volumen
      IMPORTING iv_kunnr             TYPE vbak-kunnr
                iv_waerk             TYPE vbak-waerk
                iv_total             TYPE vbak-netwr
      RETURNING VALUE(rv_porcentaje) TYPE ty_porcentaje.
ENDCLASS.


CLASS zcl_sd_descuento_pedido IMPLEMENTATION.

  METHOD calcular.
    DATA(lv_porcentaje) = COND ty_porcentaje(
      WHEN iv_auart = c_auart_devolucion
        THEN '-0.02'
      WHEN line_exists( tipos_con_descuento( )[ table_line = iv_auart ] )
        THEN porcentaje_volumen( iv_kunnr = iv_kunnr
                                 iv_waerk = iv_waerk
                                 iv_total = iv_total )
      ELSE 0 ).

    rv_descuento = iv_total * lv_porcentaje.
  ENDMETHOD.


  METHOD porcentaje_volumen.
    " Mismas reglas y mismos límites estrictos (>) que el legacy.
    IF iv_total > c_umbral_alto.
      rv_porcentaje = COND #(
        WHEN line_exists( clientes_preferenciales( )[ table_line = iv_kunnr ] ) THEN '0.15'
        WHEN iv_waerk = 'USD' THEN '0.10'
        WHEN iv_waerk = 'MXN' THEN '0.08'
        ELSE '0.05' ).
    ELSEIF iv_total > c_umbral_medio.
      rv_porcentaje = COND #( WHEN iv_waerk = 'MXN' THEN '0.04' ELSE '0.03' ).
    ELSE.
      rv_porcentaje = 0.
    ENDIF.
  ENDMETHOD.


  METHOD es_descuento_alto.
    IF iv_total = 0.
      rv_alto = abap_false.
      RETURN.
    ENDIF.
    rv_alto = xsdbool( iv_descuento / iv_total > c_umbral_desc_alto ).
  ENDMETHOD.


  METHOD tipos_con_descuento.
    rt_auart = VALUE #( ( 'TA' ) ( 'ZOR' ) ( 'ZOR2' ) ).
  ENDMETHOD.


  METHOD clientes_preferenciales.
    rt_kunnr = VALUE #( ( '0000001000' ) ( '0000001001' ) ).
  ENDMETHOD.

ENDCLASS.
