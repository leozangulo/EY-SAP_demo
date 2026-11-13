*&---------------------------------------------------------------------*
*& Function Z_SD_BLOQUEAR_PEDIDO  (grupo ZSD_BLOQ)  -  WRAPPER DE COMPATIBILIDAD
*&---------------------------------------------------------------------*
*& La lógica vive en ZCL_SD_BLOQUEO_PEDIDO. Esta función se conserva solo
*& para no romper llamadores externos y debe darse de baja cuando todos
*& migren a la clase.
*&
*& Cambios de interfaz respecto al legacy:
*&  - Nueva excepción ERROR_BLOQUEO (motivo inválido, error de BAPI o de log).
*&    Los llamadores que no la declaren en EXCEPTIONS terminarán con error
*&    de ejecución si ocurre; antes esos errores pasaban en silencio.
*&  - NO_ENCONTRADO conserva el comportamiento legacy: MESSAGE e001(zsd) RAISING,
*&    es decir, mensaje de error si el llamador no declara la excepción.
*&  - Sin backdoor para JPEREZ / DDIC.
*&  - COMMIT/ROLLBACK se hace aquí (comportamiento compatible con el legacy),
*&    ya que la clase no los ejecuta.
*&---------------------------------------------------------------------*
FUNCTION z_sd_bloquear_pedido.
*"----------------------------------------------------------------------
*"*"Interfase local:
*"  IMPORTING
*"     VALUE(I_VBELN) TYPE  VBAK-VBELN
*"     VALUE(I_MOTIV) TYPE  CHAR2
*"  EXCEPTIONS
*"      NO_ENCONTRADO
*"      ERROR_BLOQUEO
*"----------------------------------------------------------------------

  TRY.
      DATA(lo_bloqueo) = NEW zcl_sd_bloqueo_pedido( ).
      lo_bloqueo->bloquear( iv_vbeln = i_vbeln iv_motiv = i_motiv ).

      CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
        EXPORTING
          wait = abap_true.

    CATCH zcx_sd_bloqueo INTO DATA(lx_bloqueo).
      CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.

      IF lx_bloqueo->mv_causa = zcx_sd_bloqueo=>c_causa-no_encontrado.
        MESSAGE e001(zsd) WITH i_vbeln RAISING no_encontrado.
      ENDIF.
      RAISE error_bloqueo.
  ENDTRY.

ENDFUNCTION.
