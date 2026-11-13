"! Excepción de negocio para el bloqueo de pedidos de venta.
"! Reemplaza los MESSAGE ... RAISING y los SY-SUBRC sin validar del legacy.
CLASS zcx_sd_bloqueo DEFINITION
  PUBLIC
  INHERITING FROM cx_static_check
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    CONSTANTS:
      BEGIN OF c_causa,
        no_encontrado   TYPE c LENGTH 1 VALUE 'N',
        motivo_invalido TYPE c LENGTH 1 VALUE 'M',
        error_bapi      TYPE c LENGTH 1 VALUE 'B',
        error_log       TYPE c LENGTH 1 VALUE 'L',
      END OF c_causa.

    DATA mv_causa   TYPE c LENGTH 1 READ-ONLY.
    DATA mv_mensaje TYPE string READ-ONLY.

    METHODS constructor
      IMPORTING
        textid     LIKE textid OPTIONAL
        previous   LIKE previous OPTIONAL
        !i_causa   TYPE c
        !i_mensaje TYPE string.
ENDCLASS.


CLASS zcx_sd_bloqueo IMPLEMENTATION.
  METHOD constructor.
    super->constructor( textid = textid previous = previous ).
    mv_causa   = i_causa.
    mv_mensaje = i_mensaje.
  ENDMETHOD.
ENDCLASS.
