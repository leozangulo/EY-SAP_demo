"! Bloqueo de facturación de pedidos de venta.
"! Reemplaza la lógica de la función Z_SD_BLOQUEAR_PEDIDO (que queda como wrapper).
"!
"! Diferencias de diseño frente al legacy:
"! - Usa BAPI_SALESORDER_CHANGE en lugar de UPDATE directo a VBAK (el BAPI toma el
"!   bloqueo de enqueue del pedido y respeta la lógica estándar de SD).
"! - NO ejecuta COMMIT WORK ni ROLLBACK: la unidad lógica de trabajo es del llamador.
"! - Sin backdoor por usuario.
"! - Motivo inválido => excepción (el legacy desbloqueaba el pedido en silencio).
"! - Todos los errores se informan mediante ZCX_SD_BLOQUEO.
CLASS zcl_sd_bloqueo_pedido DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES:
      BEGIN OF ty_motivo,
        faksk TYPE vbak-faksk,
        texto TYPE c LENGTH 60,
      END OF ty_motivo.

    CONSTANTS:
      c_motivo_credito   TYPE c LENGTH 2 VALUE '01',
      c_motivo_cobranza  TYPE c LENGTH 2 VALUE '02',
      c_motivo_revision  TYPE c LENGTH 2 VALUE '03'.

    "! Bloquea la facturación del pedido y registra el bloqueo en ZSD_BLOQ_LOG.
    "! No hace COMMIT. Si se lanza una excepción, el llamador debe hacer ROLLBACK.
    "! @parameter iv_vbeln | Pedido de venta
    "! @parameter iv_motiv | Motivo: 01 crédito, 02 cobranza, 03 revisión manual
    "! @parameter rv_notificado | abap_false si la notificación falló o se omitió.
    "!                           El bloqueo ya está hecho aunque sea false.
    "! @raising zcx_sd_bloqueo | Pedido inexistente, motivo inválido, error del BAPI o del log
    METHODS bloquear
      IMPORTING iv_vbeln             TYPE vbak-vbeln
                iv_motiv             TYPE clike
      RETURNING VALUE(rv_notificado) TYPE abap_bool
      RAISING   zcx_sd_bloqueo.

    "! Traduce el motivo funcional al código de bloqueo de facturación (FAKSK).
    "! @raising zcx_sd_bloqueo | Motivo no contemplado
    METHODS resolver_motivo
      IMPORTING iv_motiv         TYPE clike
      RETURNING VALUE(rs_motivo) TYPE ty_motivo
      RAISING   zcx_sd_bloqueo.

  PRIVATE SECTION.
    "! Evita la recursión indirecta bloquear -> notificar -> bloquear.
    CLASS-DATA gv_notificando TYPE abap_bool.

    METHODS validar_existencia
      IMPORTING iv_vbeln TYPE vbak-vbeln
      RAISING   zcx_sd_bloqueo.

    METHODS aplicar_bloqueo
      IMPORTING iv_vbeln  TYPE vbak-vbeln
                is_motivo TYPE ty_motivo
      RAISING   zcx_sd_bloqueo.

    METHODS registrar_log
      IMPORTING iv_vbeln  TYPE vbak-vbeln
                iv_motiv  TYPE clike
                is_motivo TYPE ty_motivo
      RAISING   zcx_sd_bloqueo.

    METHODS notificar
      IMPORTING iv_vbeln             TYPE vbak-vbeln
                is_motivo            TYPE ty_motivo
      RETURNING VALUE(rv_notificado) TYPE abap_bool.
ENDCLASS.


CLASS zcl_sd_bloqueo_pedido IMPLEMENTATION.

  METHOD bloquear.
    " Reentrada desde la notificación (Z_SD_NOTIFICAR_BLOQUEO -> Z_SD_BLOQUEAR_PEDIDO):
    " se ignora para cortar la recursión indirecta del legacy (H-18) ANTES de tocar datos.
    IF gv_notificando = abap_true.
      rv_notificado = abap_false.
      RETURN.
    ENDIF.

    DATA(ls_motivo) = resolver_motivo( iv_motiv ).
    validar_existencia( iv_vbeln ).
    aplicar_bloqueo( iv_vbeln = iv_vbeln is_motivo = ls_motivo ).
    registrar_log( iv_vbeln = iv_vbeln iv_motiv = iv_motiv is_motivo = ls_motivo ).
    rv_notificado = notificar( iv_vbeln = iv_vbeln is_motivo = ls_motivo ).
  ENDMETHOD.


  METHOD resolver_motivo.
    CASE iv_motiv.
      WHEN c_motivo_credito.
        rs_motivo = VALUE #( faksk = '01' texto = 'Limite de credito excedido' ).
      WHEN c_motivo_cobranza.
        rs_motivo = VALUE #( faksk = '02' texto = 'Cliente en cobranza' ).
      WHEN c_motivo_revision.
        rs_motivo = VALUE #( faksk = '10' texto = 'Revision manual' ).
      WHEN OTHERS.
        RAISE EXCEPTION TYPE zcx_sd_bloqueo
          EXPORTING
            i_causa   = zcx_sd_bloqueo=>c_causa-motivo_invalido
            i_mensaje = |Motivo de bloqueo no valido: '{ iv_motiv }'|.
    ENDCASE.
  ENDMETHOD.


  METHOD validar_existencia.
    SELECT SINGLE vbeln FROM vbak
      WHERE vbeln = @iv_vbeln
      INTO @DATA(lv_vbeln).
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zcx_sd_bloqueo
        EXPORTING
          i_causa   = zcx_sd_bloqueo=>c_causa-no_encontrado
          i_mensaje = |Pedido { iv_vbeln ALPHA = OUT } no encontrado|.
    ENDIF.
  ENDMETHOD.


  METHOD aplicar_bloqueo.
    DATA lt_return TYPE STANDARD TABLE OF bapiret2 WITH EMPTY KEY.

    DATA(ls_header)  = VALUE bapisdh1( bill_block = is_motivo-faksk ).
    DATA(ls_headerx) = VALUE bapisdh1x( updateflag = 'U' bill_block = abap_true ).

    CALL FUNCTION 'BAPI_SALESORDER_CHANGE'
      EXPORTING
        salesdocument    = iv_vbeln
        order_header_in  = ls_header
        order_header_inx = ls_headerx
      TABLES
        return           = lt_return.

    " Cualquier E o A (error / abort) invalida la operación completa.
    READ TABLE lt_return INTO DATA(ls_error)
         WITH KEY type = 'E'.
    IF sy-subrc <> 0.
      READ TABLE lt_return INTO ls_error WITH KEY type = 'A'.
    ENDIF.
    IF sy-subrc = 0.
      RAISE EXCEPTION TYPE zcx_sd_bloqueo
        EXPORTING
          i_causa   = zcx_sd_bloqueo=>c_causa-error_bapi
          i_mensaje = |BAPI_SALESORDER_CHANGE: { ls_error-message }|.
    ENDIF.
  ENDMETHOD.


  METHOD registrar_log.
    DATA(ls_log) = VALUE zsd_bloq_log( vbeln = iv_vbeln
                                       datum = sy-datum
                                       uzeit = sy-uzeit
                                       uname = sy-uname
                                       motiv = iv_motiv
                                       texto = is_motivo-texto ).

    INSERT zsd_bloq_log FROM @ls_log.
    IF sy-subrc <> 0.
      " Clave duplicada u otro fallo: se informa en lugar de perder la auditoría en silencio.
      RAISE EXCEPTION TYPE zcx_sd_bloqueo
        EXPORTING
          i_causa   = zcx_sd_bloqueo=>c_causa-error_log
          i_mensaje = |No se pudo registrar el bloqueo de { iv_vbeln ALPHA = OUT } en ZSD_BLOQ_LOG|.
    ENDIF.
  ENDMETHOD.


  METHOD notificar.
    gv_notificando = abap_true.
    TRY.
        CALL FUNCTION 'Z_SD_NOTIFICAR_BLOQUEO'
          EXPORTING
            i_vbeln = iv_vbeln
            i_texto = is_motivo-texto
          EXCEPTIONS
            OTHERS  = 1.
        rv_notificado = xsdbool( sy-subrc = 0 ).
      CATCH cx_root.
        rv_notificado = abap_false.
    ENDTRY.
    gv_notificando = abap_false.
  ENDMETHOD.

ENDCLASS.
