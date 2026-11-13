*"* use this source file for your ABAP unit test classes
CLASS ltc_bloqueo DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    DATA mo_cut TYPE REF TO zcl_sd_bloqueo_pedido.

    METHODS setup.

    METHODS motivo_01_credito          FOR TESTING RAISING cx_static_check.
    METHODS motivo_02_cobranza         FOR TESTING RAISING cx_static_check.
    METHODS motivo_03_mapea_a_10       FOR TESTING RAISING cx_static_check.
    " Corrige H-16: el legacy dejaba FAKSK vacío (desbloqueaba) con motivo inválido
    METHODS motivo_invalido_excepcion  FOR TESTING RAISING cx_static_check.
    METHODS motivo_vacio_excepcion     FOR TESTING RAISING cx_static_check.
ENDCLASS.


CLASS ltc_bloqueo IMPLEMENTATION.

  METHOD setup.
    mo_cut = NEW #( ).
  ENDMETHOD.

  METHOD motivo_01_credito.
    DATA(ls_motivo) = mo_cut->resolver_motivo( '01' ).
    cl_abap_unit_assert=>assert_equals( exp = '01' act = ls_motivo-faksk ).
    cl_abap_unit_assert=>assert_not_initial( ls_motivo-texto ).
  ENDMETHOD.

  METHOD motivo_02_cobranza.
    cl_abap_unit_assert=>assert_equals( exp = '02' act = mo_cut->resolver_motivo( '02' )-faksk ).
  ENDMETHOD.

  METHOD motivo_03_mapea_a_10.
    cl_abap_unit_assert=>assert_equals( exp = '10' act = mo_cut->resolver_motivo( '03' )-faksk ).
  ENDMETHOD.

  METHOD motivo_invalido_excepcion.
    TRY.
        mo_cut->resolver_motivo( '99' ).
        cl_abap_unit_assert=>fail( 'Debio lanzar ZCX_SD_BLOQUEO' ).
      CATCH zcx_sd_bloqueo INTO DATA(lx).
        cl_abap_unit_assert=>assert_equals(
          exp = zcx_sd_bloqueo=>c_causa-motivo_invalido
          act = lx->mv_causa ).
    ENDTRY.
  ENDMETHOD.

  METHOD motivo_vacio_excepcion.
    TRY.
        mo_cut->resolver_motivo( '' ).
        cl_abap_unit_assert=>fail( 'Debio lanzar ZCX_SD_BLOQUEO' ).
      CATCH zcx_sd_bloqueo INTO DATA(lx).
        cl_abap_unit_assert=>assert_equals(
          exp = zcx_sd_bloqueo=>c_causa-motivo_invalido
          act = lx->mv_causa ).
    ENDTRY.
  ENDMETHOD.

ENDCLASS.
