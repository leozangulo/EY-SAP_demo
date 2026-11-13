*&---------------------------------------------------------------------*
*& Report  ZSD_PEDIDOS_LEGACY
*&---------------------------------------------------------------------*
*& CODIGO LEGACY INTENCIONAL - SOLO PARA PRACTICA DE MODERNIZACION
*& Autor : JPEREZ   Fecha: 14.03.2004   (ultimo cambio: 02.11.2011 MGOMEZ)
*& Desc  : Reporte de pedidos de venta con calculo de descuento y
*&         bloqueo de credito. NO TOCAR, funciona en produccion.
*&---------------------------------------------------------------------*
REPORT zsd_pedidos_legacy LINE-SIZE 200 NO STANDARD PAGE HEADING.

TABLES: vbak, vbap, kna1, knkk.

* Tabla con header line (obsoleto)
DATA: BEGIN OF it_ped OCCURS 0,
        vbeln LIKE vbak-vbeln,
        kunnr LIKE vbak-kunnr,
        auart LIKE vbak-auart,
        netwr LIKE vbak-netwr,
        waerk LIKE vbak-waerk,
        name1 LIKE kna1-name1,
        desc  TYPE p DECIMALS 2,
        flag,
      END OF it_ped.

DATA: it_pos LIKE vbap OCCURS 0 WITH HEADER LINE.
DATA: w_total TYPE p DECIMALS 2,
      w_desc  TYPE p DECIMALS 2,
      w_cont  TYPE i,
      w_msg(100),
      w_ok,
      w_tmp(20).

SELECT-OPTIONS: s_vbeln FOR vbak-vbeln,
                s_kunnr FOR vbak-kunnr,
                s_erdat FOR vbak-erdat.
PARAMETERS: p_vkorg LIKE vbak-vkorg DEFAULT '1000',
            p_upd   AS CHECKBOX,
            p_bloq  AS CHECKBOX DEFAULT 'X'.

START-OF-SELECTION.
  PERFORM leer_datos.
  PERFORM procesar.
  PERFORM mostrar.

*&---------------------------------------------------------------------*
FORM leer_datos.
* SELECT * y sin validar sy-subrc
  SELECT * FROM vbak
    WHERE vbeln IN s_vbeln
      AND kunnr IN s_kunnr
      AND erdat IN s_erdat.

    MOVE-CORRESPONDING vbak TO it_ped.

*   SELECT dentro de loop (N+1) y sin SINGLE por clave completa
    SELECT * FROM kna1 WHERE kunnr = vbak-kunnr.
      it_ped-name1 = kna1-name1.
    ENDSELECT.

    APPEND it_ped.
    CLEAR it_ped.
  ENDSELECT.
ENDFORM.

*&---------------------------------------------------------------------*
FORM procesar.
  LOOP AT it_ped.

    CLEAR: w_total, w_desc, w_ok.

*   Sin AUTHORITY-CHECK sobre organizacion de ventas
    SELECT * FROM vbap INTO TABLE it_pos
      WHERE vbeln = it_ped-vbeln.

    LOOP AT it_pos.
      w_total = w_total + it_pos-netwr.
    ENDLOOP.

*   Logica de descuento anidada, numeros magicos y tipos de doc hardcodeados
    IF it_ped-auart = 'ZOR' OR it_ped-auart = 'ZOR2' OR it_ped-auart = 'TA'.
      IF w_total > 100000.
        IF it_ped-kunnr = '0000001000' OR it_ped-kunnr = '0000001001'.
          w_desc = w_total * '0.15'.
        ELSE.
          IF it_ped-waerk = 'USD'.
            w_desc = w_total * '0.10'.
          ELSEIF it_ped-waerk = 'MXN'.
            w_desc = w_total * '0.08'.
          ELSE.
            w_desc = w_total * '0.05'.
          ENDIF.
        ENDIF.
      ELSEIF w_total > 50000.
        IF it_ped-waerk = 'MXN'.
          w_desc = w_total * '0.04'.
        ELSE.
          w_desc = w_total * '0.03'.
        ENDIF.
      ELSE.
        w_desc = 0.
      ENDIF.
    ELSE.
      IF it_ped-auart = 'ZRE'.
*       Devoluciones: el descuento se invierte (nadie recuerda por que)
        w_desc = w_total * '-0.02'.
      ENDIF.
    ENDIF.

*   Division sin validar cero
    w_tmp = w_desc / w_total.
    IF w_tmp > '0.12'.
      it_ped-flag = 'X'.
    ENDIF.

    it_ped-desc  = w_desc.
    it_ped-netwr = w_total - w_desc.

*   Bloqueo de credito: lee KNKK dentro del loop, ignora sy-subrc
    IF p_bloq = 'X'.
      SELECT SINGLE * FROM knkk
        WHERE kunnr = it_ped-kunnr
          AND kkber = p_vkorg.
      IF knkk-klimk < it_ped-netwr.
        CALL FUNCTION 'Z_SD_BLOQUEAR_PEDIDO'
          EXPORTING
            i_vbeln = it_ped-vbeln
            i_motiv = '01'.
        it_ped-flag = 'B'.
      ENDIF.
    ENDIF.

    MODIFY it_ped.
    w_cont = w_cont + 1.

*   COMMIT dentro del loop, sin manejo de errores
    IF p_upd = 'X'.
      UPDATE vbak SET netwr = it_ped-netwr
                  WHERE vbeln = it_ped-vbeln.
      COMMIT WORK.
    ENDIF.

  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
FORM mostrar.
  WRITE: / 'Pedido', 15 'Cliente', 30 'Nombre', 75 'Neto', 95 'Desc', 110 'Est'.
  ULINE.
  LOOP AT it_ped.
    WRITE: / it_ped-vbeln, it_ped-kunnr, it_ped-name1,
             it_ped-netwr, it_ped-desc, it_ped-flag.
*   Color por flag con IFs sueltos
    IF it_ped-flag = 'B'.
      WRITE 'BLOQUEADO' COLOR COL_NEGATIVE.
    ENDIF.
    IF it_ped-flag = 'X'.
      WRITE 'DESC ALTO' COLOR COL_TOTAL.
    ENDIF.
  ENDLOOP.
  WRITE: / 'Procesados:', w_cont.
ENDFORM.
