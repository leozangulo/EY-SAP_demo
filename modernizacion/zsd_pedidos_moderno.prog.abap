*&---------------------------------------------------------------------*
*& Report  ZSD_PEDIDOS_MODERNO
*&---------------------------------------------------------------------*
*& Reemplaza a ZSD_PEDIDOS_LEGACY.
*& Calcula descuento por pedido, valida crédito y bloquea la facturación
*& de los pedidos que exceden el límite del cliente.
*&
*& Ver MODERNIZACION.md para el mapeo de hallazgos y los cambios de
*& comportamiento que requieren confirmación de negocio.
*&---------------------------------------------------------------------*
REPORT zsd_pedidos_moderno.

DATA gv_vbeln TYPE vbak-vbeln.
DATA gv_kunnr TYPE vbak-kunnr.
DATA gv_erdat TYPE vbak-erdat.

SELECT-OPTIONS: s_vbeln FOR gv_vbeln,
                s_kunnr FOR gv_kunnr,
                s_erdat FOR gv_erdat.
" Área de control de crédito. En el legacy se reutilizaba p_vkorg (org. de ventas) por error.
PARAMETERS p_kkber TYPE knkk-kkber DEFAULT '1000'.
PARAMETERS p_bloq  AS CHECKBOX DEFAULT 'X'.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    METHODS run.

  PRIVATE SECTION.
    CONSTANTS:
      c_motivo_credito TYPE c LENGTH 2 VALUE '01',
      c_actvt_mostrar  TYPE c LENGTH 2 VALUE '03',
      c_actvt_cambiar  TYPE c LENGTH 2 VALUE '02'.

    TYPES:
      BEGIN OF ty_pedido,
        vbeln      TYPE vbak-vbeln,
        kunnr      TYPE vbak-kunnr,
        vkorg      TYPE vbak-vkorg,
        auart      TYPE vbak-auart,
        waerk      TYPE vbak-waerk,
        name1      TYPE kna1-name1,
        total      TYPE vbak-netwr,
        descuento  TYPE vbak-netwr,
        neto       TYPE vbak-netwr,
        desc_alto  TYPE abap_bool,
        estado     TYPE string,
      END OF ty_pedido,
      ty_pedidos TYPE STANDARD TABLE OF ty_pedido WITH EMPTY KEY,
      BEGIN OF ty_credito,
        kunnr TYPE knkk-kunnr,
        klimk TYPE knkk-klimk,
      END OF ty_credito,
      ty_creditos TYPE SORTED TABLE OF ty_credito WITH UNIQUE KEY kunnr.

    DATA mt_pedidos   TYPE ty_pedidos.
    DATA mt_creditos  TYPE ty_creditos.
    DATA mo_descuento TYPE REF TO zcl_sd_descuento_pedido.
    DATA mo_bloqueo   TYPE REF TO zcl_sd_bloqueo_pedido.

    METHODS leer_datos.
    METHODS filtrar_autorizados.
    METHODS leer_creditos.
    METHODS procesar.
    METHODS tiene_autorizacion
      IMPORTING iv_vkorg       TYPE vbak-vkorg
                iv_actvt       TYPE c
      RETURNING VALUE(rv_auth) TYPE abap_bool.
    METHODS evaluar_credito
      CHANGING cs_pedido TYPE ty_pedido.
    METHODS bloquear_pedido
      CHANGING cs_pedido TYPE ty_pedido.
    METHODS mostrar.
ENDCLASS.


CLASS lcl_app IMPLEMENTATION.

  METHOD run.
    mo_descuento = NEW #( ).
    mo_bloqueo   = NEW #( ).
    leer_datos( ).
    filtrar_autorizados( ).
    IF mt_pedidos IS INITIAL.
      MESSAGE 'No se encontraron pedidos con los criterios indicados' TYPE 'S'.
      RETURN.
    ENDIF.
    IF p_bloq = abap_true.
      leer_creditos( ).
    ENDIF.
    procesar( ).
    mostrar( ).
  ENDMETHOD.


  METHOD leer_datos.
    " Una sola consulta: cabecera + total de posiciones + nombre del cliente.
    " Reemplaza los SELECT anidados (N+1) sobre KNA1 y VBAP del legacy.
    SELECT vbak~vbeln, vbak~kunnr, vbak~vkorg, vbak~auart, vbak~waerk,
           kna1~name1,
           SUM( vbap~netwr ) AS total
      FROM vbak
      LEFT OUTER JOIN vbap ON vbap~vbeln = vbak~vbeln
      LEFT OUTER JOIN kna1 ON kna1~kunnr = vbak~kunnr
      WHERE vbak~vbeln IN @s_vbeln
        AND vbak~kunnr IN @s_kunnr
        AND vbak~erdat IN @s_erdat
      GROUP BY vbak~vbeln, vbak~kunnr, vbak~vkorg, vbak~auart, vbak~waerk, kna1~name1
      ORDER BY vbak~vbeln
      INTO CORRESPONDING FIELDS OF TABLE @mt_pedidos.
  ENDMETHOD.


  METHOD filtrar_autorizados.
    " Los pedidos de organizaciones de ventas sin autorización de visualización
    " se excluyen por completo (ni se listan ni se procesan). El legacy no validaba.
    DATA lv_omitidos TYPE i.
    LOOP AT mt_pedidos ASSIGNING FIELD-SYMBOL(<ped>).
      IF tiene_autorizacion( iv_vkorg = <ped>-vkorg iv_actvt = c_actvt_mostrar ) = abap_false.
        DELETE mt_pedidos.
        lv_omitidos = lv_omitidos + 1.
      ENDIF.
    ENDLOOP.
    IF lv_omitidos > 0.
      MESSAGE |{ lv_omitidos } pedido(s) omitido(s) por falta de autorizacion| TYPE 'S'.
    ENDIF.
  ENDMETHOD.


  METHOD leer_creditos.
    " Se lee una sola vez para todos los clientes (el legacy leía KNKK por cada pedido).
    DATA(lt_clientes) = mt_pedidos.
    SORT lt_clientes BY kunnr.
    DELETE ADJACENT DUPLICATES FROM lt_clientes COMPARING kunnr.

    SELECT kunnr, klimk
      FROM knkk
      FOR ALL ENTRIES IN @lt_clientes
      WHERE kunnr = @lt_clientes-kunnr
        AND kkber = @p_kkber
      INTO TABLE @mt_creditos.
  ENDMETHOD.


  METHOD procesar.
    LOOP AT mt_pedidos ASSIGNING FIELD-SYMBOL(<ped>).

      <ped>-descuento = mo_descuento->calcular( iv_auart = <ped>-auart
                                                iv_kunnr = <ped>-kunnr
                                                iv_waerk = <ped>-waerk
                                                iv_total = <ped>-total ).
      <ped>-neto      = <ped>-total - <ped>-descuento.
      <ped>-desc_alto = mo_descuento->es_descuento_alto( iv_descuento = <ped>-descuento
                                                         iv_total     = <ped>-total ).
      IF <ped>-desc_alto = abap_true.
        <ped>-estado = 'DESC ALTO'.
      ENDIF.

      IF p_bloq = abap_true.
        evaluar_credito( CHANGING cs_pedido = <ped> ).
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD tiene_autorizacion.
    AUTHORITY-CHECK OBJECT 'V_VBAK_VKO'
      ID 'VKORG' FIELD iv_vkorg
      ID 'VTWEG' DUMMY
      ID 'SPART' DUMMY
      ID 'ACTVT' FIELD iv_actvt.
    rv_auth = xsdbool( sy-subrc = 0 ).
  ENDMETHOD.


  METHOD evaluar_credito.
    " Cliente sin registro de crédito: NO se bloquea y se informa.
    " (El legacy usaba el límite del cliente anterior; ver H-03.)
    READ TABLE mt_creditos ASSIGNING FIELD-SYMBOL(<cred>)
         WITH TABLE KEY kunnr = cs_pedido-kunnr.
    IF sy-subrc <> 0.
      cs_pedido-estado = 'SIN REGISTRO DE CREDITO'.
      RETURN.
    ENDIF.

    IF <cred>-klimk < cs_pedido-neto.
      bloquear_pedido( CHANGING cs_pedido = cs_pedido ).
    ENDIF.
  ENDMETHOD.


  METHOD bloquear_pedido.
    IF tiene_autorizacion( iv_vkorg = cs_pedido-vkorg iv_actvt = c_actvt_cambiar ) = abap_false.
      cs_pedido-estado = 'EXCEDE CREDITO - SIN AUTORIZACION PARA BLOQUEAR'.
      RETURN.
    ENDIF.

    TRY.
        DATA(lv_notificado) = mo_bloqueo->bloquear( iv_vbeln = cs_pedido-vbeln
                                                    iv_motiv = c_motivo_credito ).
        " Una unidad lógica de trabajo por pedido: un fallo no revierte los anteriores.
        CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
          EXPORTING
            wait = abap_true.

        cs_pedido-estado = COND #( WHEN lv_notificado = abap_true
                                   THEN 'BLOQUEADO'
                                   ELSE 'BLOQUEADO (notificacion fallida)' ).

      CATCH zcx_sd_bloqueo INTO DATA(lx).
        CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
        cs_pedido-estado = |ERROR: { lx->mv_mensaje }|.
    ENDTRY.
  ENDMETHOD.


  METHOD mostrar.
    TRY.
        cl_salv_table=>factory( IMPORTING r_salv_table = DATA(lo_alv)
                                CHANGING  t_table      = mt_pedidos ).
        lo_alv->get_functions( )->set_all( abap_true ).
        lo_alv->get_columns( )->set_optimize( abap_true ).
        lo_alv->get_columns( )->get_column( 'DESC_ALTO' )->set_technical( abap_true ).
        lo_alv->get_display_settings( )->set_list_header(
          |Pedidos procesados: { lines( mt_pedidos ) }| ).
        lo_alv->display( ).
      CATCH cx_salv_msg cx_salv_not_found INTO DATA(lx_alv).
        MESSAGE lx_alv TYPE 'E'.
    ENDTRY.
  ENDMETHOD.

ENDCLASS.


START-OF-SELECTION.
  NEW lcl_app( )->run( ).
