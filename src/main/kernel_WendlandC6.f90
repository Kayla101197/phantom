!--------------------------------------------------------------------------!
! The Phantom Smoothed Particle Hydrodynamics code, by Daniel Price et al. !
! Copyright (c) 2007-2024 The Authors (see AUTHORS)                        !
! See LICENCE file for usage and distribution conditions                   !
! http://phantomsph.github.io/                                             !
!--------------------------------------------------------------------------!
module kernel
!
! This module implements the Wendland 2/3D C^6 kernel
!   DO NOT EDIT - auto-generated by kernels.py
!
! :References: None
!
! :Owner: Daniel Price
!
! :Runtime parameters: None
!
! :Dependencies: physcon
!
 use physcon, only:pi
 implicit none
 character(len=17), public :: kernelname = 'Wendland 2/3D C^6'
 real, parameter, public  :: radkern  = 2.
 real, parameter, public  :: radkern2 = 4.
 real, parameter, public  :: cnormk = 1365./(512.*pi)
 real, parameter, public  :: wab0 = 1., gradh0 = -3.*wab0
 real, parameter, public  :: dphidh0 = 245./128.
 real, parameter, public  :: cnormk_drag = 1365./(256.*pi)
 real, parameter, public  :: hfact_default = 1.6
 real, parameter, public  :: av_factor = 0.875

contains

pure subroutine get_kernel(q2,q,wkern,grkern)
 real, intent(in)  :: q2,q
 real, intent(out) :: wkern,grkern

 !--Wendland 2/3D C^6
 if (q < 2.) then
    wkern  = (0.5*q - 1.)**8*(4.*q2*q + 6.25*q2 + 4.*q + 1.)
    grkern = q*(0.5*q - 1.)**7*(22.*q2 + 19.25*q + 5.5)
 else
    wkern  = 0.
    grkern = 0.
 endif

end subroutine get_kernel

pure elemental real function wkern(q2,q)
 real, intent(in) :: q2,q

 if (q < 2.) then
    wkern = (0.5*q - 1.)**8*(4.*q2*q + 6.25*q2 + 4.*q + 1.)
 else
    wkern = 0.
 endif

end function wkern

pure elemental real function grkern(q2,q)
 real, intent(in) :: q2,q

 if (q < 2.) then
    grkern = q*(0.5*q - 1.)**7*(22.*q2 + 19.25*q + 5.5)
 else
    grkern = 0.
 endif

end function grkern

pure subroutine get_kernel_grav1(q2,q,wkern,grkern,dphidh)
 real, intent(in)  :: q2,q
 real, intent(out) :: wkern,grkern,dphidh
 real :: q4, q6, q8

 if (q < 2.) then
    q4 = q2*q2
    q6 = q4*q2
    q8 = q6*q2
    wkern  = (0.5*q - 1.)**8*(4.*q2*q + 6.25*q2 + 4.*q + 1.)
    grkern = q*(0.5*q - 1.)**7*(22.*q2 + 19.25*q + 5.5)
    dphidh = -105.*q**13/8192. + 105105.*q6*q6/524288. - 1365.*q6*q4*q/1024. + &
                 315315.*q6*q4/65536. - 5005.*q8*q/512. + 315315.*q8/32768. - &
                 15015.*q6/2048. + 15015.*q4/2048. - 1365.*q2/256. + 245./128.
 else
    wkern  = 0.
    grkern = 0.
    dphidh = 0.
 endif

end subroutine get_kernel_grav1

pure subroutine kernel_softening(q2,q,potensoft,fsoft)
 real, intent(in)  :: q2,q
 real, intent(out) :: potensoft,fsoft
 real :: q4, q6, q8

 if (q < 2.) then
    q4 = q2*q2
    q6 = q4*q2
    q8 = q6*q2
    potensoft = 15.*q**13/16384. - 8085.*q6*q6/524288. + 455.*q6*q4*q/4096. - &
                 28665.*q6*q4/65536. + 1001.*q8*q/1024. - 35035.*q8/32768. + &
                 2145.*q6/2048. - 3003.*q4/2048. + 455.*q2/256. - 245./128.
    fsoft     = q*(1560.*q6*q4*q - 24255.*q6*q4 + 160160.*q8*q - 573300.*q8 + &
                 1153152.*q6*q - 1121120.*q6 + 823680.*q4 - 768768.*q2 + &
                 465920.)/131072.
 else
    potensoft = -1./q
    fsoft     = 1./q2
 endif

end subroutine kernel_softening

!------------------------------------------
! gradient acceleration kernel needed for
! use in Forward symplectic integrator
!------------------------------------------
pure subroutine kernel_grad_soft(q2,q,gsoft)
 real, intent(in)  :: q2,q
 real, intent(out) :: gsoft
 real :: q4, q6, q8

 if (q < 2.) then
    q4 = q2*q2
    q6 = q4*q2
    q8 = q6*q2
    gsoft = 3.*q2*q*(2860.*q8*q - 40425.*q8 + 240240.*q6*q - 764400.*q6 + &
                 1345344.*q4*q - 1121120.*q4 + 549120.*q2 - 256256.)/65536.
 else
    gsoft = -3./q2
 endif

end subroutine kernel_grad_soft

!------------------------------------------
! double-humped version of the kernel for
! use in drag force calculations
!------------------------------------------
pure elemental real function wkern_drag(q2,q)
 real, intent(in) :: q2,q

 !--double hump Wendland 2/3D C^6 kernel
 if (q < 2.) then
    wkern_drag = q2*(0.5*q - 1.)**8*(4.*q2*q + 6.25*q2 + 4.*q + 1.)
 else
    wkern_drag = 0.
 endif

end function wkern_drag

end module kernel
