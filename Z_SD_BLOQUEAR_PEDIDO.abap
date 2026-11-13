*&---------------------------------------------------------------------*
*& Function Group ZSD_BLOQ  /  Modulo de funcion Z_SD_BLOQUEAR_PEDIDO
*& CODIGO LEGACY INTENCIONAL - SOLO PARA PRACTICA DE MODERNIZACION
*& Autor : JPEREZ   Fecha: 20.06.2005
*&---------------------------------------------------------------------*
FUNCTION z_sd_bloquear_pedido.
*"----------------------------------------------------------------------
*"*"Interfase local:
*"  IMPORTING
*"     VALUE(I_VBELN) LIKE  VBAK-VBELN
*"     VALUE(I_MOTIV) TYPE  C
*"  EXCEPTIONS
*"      NO_ENCONTRADO
*"----------------------------------------------------------------------

  TABLES: vbak, tvlv.

* Variables globales del grupo de funciones (estado compartido entre llamadas)
  DATA: g_ultimo LIKE vbak-vbeln,
        g_veces  TYPE i.

  DATA: l_sperr LIKE vbak-faksk,
        l_user  LIKE sy-uname,
        l_texto(60).

* Sin ENQUEUE: dos usuarios pueden modificar el mismo pedido
  SELECT SINGLE * FROM vbak WHERE vbeln = i_vbeln.
  IF sy-subrc <> 0.
    MESSAGE e001(zsd) WITH i_vbeln RAISING no_encontrado.
  ENDIF.

* Motivo hardcodeado con CASE sin WHEN OTHERS
  CASE i_motiv.
    WHEN '01'.
      l_sperr = '01'.
      l_texto = 'Limite de credito excedido'.
    WHEN '02'.
      l_sperr = '02'.
      l_texto = 'Cliente en cobranza'.
    WHEN '03'.
      l_sperr = '10'.
      l_texto = 'Revision manual'.
  ENDCASE.

* Usuario "magico" que se salta el bloqueo (backdoor)
  l_user = sy-uname.
  IF l_user = 'JPEREZ' OR l_user = 'DDIC'.
    EXIT.
  ENDIF.

* Si ya se bloqueo este mismo pedido en la llamada anterior, no repetir
  IF g_ultimo = i_vbeln.
    g_veces = g_veces + 1.
    IF g_veces > 3.
      EXIT.
    ENDIF.
  ELSE.
    g_ultimo = i_vbeln.
    g_veces  = 1.
  ENDIF.

* UPDATE directo a tabla estandar SAP en lugar de BAPI/BDC
  UPDATE vbak SET faksk = l_sperr
                  aedat = sy-datum
              WHERE vbeln = i_vbeln.

* sy-subrc no se valida; COMMIT WORK dentro del FM
  COMMIT WORK.

* Bitacora en tabla Z sin validar existencia ni clave duplicada
  INSERT INTO zsd_bloq_log VALUES
         ( i_vbeln, sy-datum, sy-uzeit, l_user, i_motiv, l_texto ).

* Llamada recursiva indirecta: notificar puede volver a bloquear
  CALL FUNCTION 'Z_SD_NOTIFICAR_BLOQUEO'
    EXPORTING
      i_vbeln = i_vbeln
      i_texto = l_texto.

ENDFUNCTION.
