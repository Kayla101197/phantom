!--------------------------------------------------------------------------!
! The Phantom Smoothed Particle Hydrodynamics code, by Daniel Price et al. !
! Copyright (c) 2007-2023 The Authors (see AUTHORS)                        !
! See LICENCE file for usage and distribution conditions                   !
! http://phantomsph.bitbucket.io/                                          !
!--------------------------------------------------------------------------!
module cooling_stamatellos
!
! Cooling method of Stamatellos et al. 2007
!
! :References: Stamatellos et al. 2007
!
! :Owner: Alison Young
!
! :Runtime parameters:
!   - EOS_file : File containing tabulated EOS values
!   - Lstar    : Luminosity of host star for calculating Tmin (Lsun)
!
! :Dependencies: eos_stamatellos, infile_utils, io, part, physcon, units
!

 implicit none
 real, public :: Lstar=0.0 ! in units of L_sun
 integer :: isink_star ! index of sink to use as illuminating star
 integer :: od_method = 4 ! default = Stamatellos+ 2007 method
 integer :: fld_opt = 1 ! by default FLD is switched on
 public :: cooling_S07,write_options_cooling_stamatellos,read_options_cooling_stamatellos
 public :: init_star

contains

subroutine init_star()
 use part,    only:nptmass,xyzmh_ptmass
 use io,      only:fatal
 integer :: i,imin
 real :: rsink2,rsink2min

 rsink2min = 0d0

 isink_star = 0
 if (od_method == 4 .and. nptmass == 0) then
    print *, "NO central star and using od_method = 4"
 elseif (nptmass == 0) then
    print *, "No stellar heating."
 elseif (nptmass == 1) then
    isink_star = 1
 else
    do i=1,nptmass
       rsink2 = xyzmh_ptmass(1,i)**2 + xyzmh_ptmass(2,i)**2 + xyzmh_ptmass(3,i)**2
       if (i==1 .or. (rsink2 < rsink2min) ) then
          rsink2min = rsink2
          imin = i
       endif
    enddo
    isink_star = imin
 endif
 if (isink_star > 0)  print *, "Using sink no. ", isink_star,&
      "at (xyz)",xyzmh_ptmass(1:3,isink_star)!"as illuminating star."
end subroutine init_star

!
! Do cooling calculation
!
! edit this to make a loop and update energy to return evolved energy array.
subroutine cooling_S07(npart,xyzh,energ,Tfloor,dudt_sph,dt)
 use io,       only:warning
 use physcon,  only:steboltz,pi,solarl,Rg,kb_on_mh,piontwo,rpiontwo
 use units,    only:umass,udist,unit_density,unit_ergg,utime,unit_pressure
 use eos_stamatellos, only:getopac_opdep,getintenerg_opdep,gradP_cool,Gpot_cool,&
          duFLD,doFLD,ttherm_store,teqi_store,opac_store
 use part,       only:xyzmh_ptmass,rhoh,massoftype,igas

 integer,intent(in) :: npart
 real,intent(in) :: dudt_sph(:),xyzh(:,:),Tfloor,dt
 real,intent(inout) :: energ(:)
 real            :: dudti_cool,ui,rhoi
 real            :: coldensi,kappaBari,kappaParti,ri2
 real            :: gmwi,Tmini4,Ti,dudti_rad,Teqi,Hstam,HLom,du_tot
 real            :: cs2,Om2,Hmod2,xi,yi,zi
 real            :: opaci,ueqi,umini,tthermi,poti,presi,Hcomb,du_FLDi
 integer         :: i

 !omp parallel do default(none) &
 !omp shared(npart,duFLD,xyzh,energ,rhoh,massoftype,igas,xyzmh_ptmass) &
 !omp shared(isink_star,pi,steboltz,solarl,Rg,doFLD,ttherm_store,teqi_store) &
 !omp shared(opac_store,Tfloor,dt,dudt_sph)
 !omp private(i,poti,du_FLDi,xi,yi,zi,ui,rhoi,ri2,coldensi,kappaBari) &
 !omp private(kappaParti,gmwi,Tmini4,dudti_rad,Teqi,Hstam,HLom,du_tot) &
 !omp private(cs2,Om2,Hmod2,opaci,ueqi,umini,tthermi,poti,presi,Hcomb)
 overpart: do i=1,npart
    poti = Gpot_cool(i)
    du_FLDi = duFLD(i)
    xi = xyzh(1,i)
    yi = xyzh(2,i)
    zi = xyzh(3,i)
    ui = energ(i)
    rhoi =  rhoh(xyzh(4,i),massoftype(igas))
    
    if (isink_star > 0) then
       ri2 = (xi-xyzmh_ptmass(1,isink_star))**2d0 &
            + (yi-xyzmh_ptmass(2,isink_star))**2d0 &
            + (zi-xyzmh_ptmass(3,isink_star))**2d0  
    endif

    ! get opacities & Ti for ui
    call getopac_opdep(ui*unit_ergg,rhoi*unit_density,kappaBari,kappaParti,&
           Ti,gmwi)
    presi = kb_on_mh*rhoi*unit_density*Ti/gmwi ! cgs
    presi = presi/unit_pressure !code units

    if (isnan(kappaBari)) then
       print *, "kappaBari is NaN\n", " ui(erg) = ", ui*unit_ergg, "rhoi=", rhoi*unit_density, "Ti=", Ti, &
            "i=", i
       stop
    endif

    select case (od_method)
    case (1)
       ! Stamatellos+ 2007 method
       coldensi = sqrt(abs(poti*rhoi)/4.d0/pi) ! G cancels out as G=1 in code
       coldensi = 0.368d0*coldensi ! n=2 in polytrope formalism Forgan+ 2009
       coldensi = coldensi*umass/udist/udist ! physical units
    case (2)
       ! Lombardi+ 2015 method of estimating the mean column density
       coldensi = 1.014d0 * presi / abs(gradP_cool(i))! 1.014d0 * P/(-gradP/rho)
       coldensi = coldensi *umass/udist/udist ! physical units
    case (3)
       ! Combined method
       HStam = sqrt(abs(poti*rhoi)/4.0d0/pi)*0.368d0/rhoi
       HLom  = 1.014d0*presi/abs(gradP_cool(i))/rhoi
       Hcomb = 1.d0/sqrt((1.0d0/HLom)**2.0d0 + (1.0d0/HStam)**2.0d0)
       coldensi = Hcomb*rhoi
       coldensi = coldensi*umass/udist/udist ! physical units
    case (4) 
       ! Modified Lombardi method
       HLom  = presi/abs(gradP_cool(i))/rhoi
       cs2 = presi/rhoi
       if (isink_star > 0 .and. ri2 > 0d0) then
          Om2 = xyzmh_ptmass(4,isink_star)/(ri2**(1.5)) !NB we are using spherical radius here
       else
          Om2 = 0d0
       endif
       Hmod2 = cs2 * piontwo / (Om2 + 8d0*rpiontwo*rhoi)
       !Q3D = Om2/(4.d0*pi*rhoi)
    !Hmod2 = (cs2/Om2) * piontwo /(1d0 + (1d0/(rpiontwo*Q3D)))
       Hcomb = 1.d0/sqrt((1.0d0/HLom)**2.0d0 + (1.0d0/Hmod2))
       coldensi = 1.014d0 * Hcomb *rhoi*umass/udist/udist ! physical units
    end select

!    Tfloor is from input parameters and is background heating
!    Stellar heating
    if (isink_star > 0 .and. Lstar > 0.d0) then
       ! Tfloor + stellar heating
       Tmini4 = Tfloor**4d0 + exp(-coldensi*kappaBari)*(Lstar*solarl/(16d0*pi*steboltz*ri2*udist*udist))
    else
       Tmini4 = Tfloor**4d0
    endif

    opaci = (coldensi**2d0)*kappaBari + (1.d0/kappaParti) ! physical units
    opac_store(i) = opaci
    dudti_rad = 4.d0*steboltz*(Tmini4 - Ti**4.d0)/opaci/unit_ergg*utime! code units

    if (doFLD) then
       ! include term from FLD
       Teqi = (du_FLDi + dudt_sph(i)) *opaci*unit_ergg/utime ! physical units
       du_tot = dudt_sph(i) + dudti_rad + du_FLDi
    else
       Teqi = dudt_sph(i)*opaci*unit_ergg/utime
       du_tot = dudt_sph(i) + dudti_rad 
    endif
  
    Teqi = Teqi/4.d0/steboltz
    Teqi = Teqi + Tmini4
    if (Teqi < Tmini4) then
       Teqi = Tmini4**(1.0/4.0)
    else
       Teqi = Teqi**(1.0/4.0)
    endif
    teqi_store(i) = Teqi
    call getintenerg_opdep(Teqi,rhoi*unit_density,ueqi)
    ueqi = ueqi/unit_ergg
        
    call getintenerg_opdep(Tmini4**(1.0/4.0),rhoi*unit_density,umini)
    umini = umini/unit_ergg

    ! calculate thermalization timescale and
    ! internal energy update -> in form where it'll work as dudtcool
    if ((du_tot) == 0.d0) then
       tthermi = 0d0
    else
       tthermi = abs((ueqi - ui)/(du_tot))
    endif

    ttherm_store(i) = tthermi

    if (tthermi == 0d0) then
       dudti_cool = 0.d0 ! condition if denominator above is zero
    else
       dudti_cool = (ui*exp(-dt/tthermi) + ueqi*(1.d0-exp(-dt/tthermi)) -ui)/dt !code units
    endif

    if (isnan(dudti_cool)) then
       !    print *, "kappaBari=",kappaBari, "kappaParti=",kappaParti
       print *, "rhoi=",rhoi, "Ti=", Ti
       print *, "opaci=",opaci,"coldensi=",coldensi,"dudt_sphi",dudt_sph(i)
       print *,  "dt=",dt,"tthermi=", tthermi,"umini=", umini
       print *, "dudti_rad=", dudti_rad ,"dudt_dlf=",du_fldi,"ueqi=",ueqi,"ui=",ui
       call warning("In Stamatellos cooling","dudticool=NaN. ui",val=ui)
       stop
    else if (dudti_cool < 0.d0 .and. abs(dudti_cool) > ui/dt) then
       dudti_cool = (umini - ui)/dt
    endif

    ! evolve energy
    energ(i) = energ(i) + dudti_cool * dt

 enddo overpart

end subroutine cooling_S07


subroutine write_options_cooling_stamatellos(iunit)
 use infile_utils, only:write_inopt
 use eos_stamatellos, only: eos_file
 integer, intent(in) :: iunit

 !N.B. Tfloor handled in cooling.F90
 call write_inopt(eos_file,'EOS_file','File containing tabulated EOS values',iunit)
 call write_inopt(od_method,'OD method',&
      'Method for estimating optical depth:(1)Stamatellos (2)Lombardi (3)combined (4)modified Lombardi',iunit)
 call write_inopt(Lstar,'Lstar','Luminosity of host star for calculating Tmin (Lsun)',iunit)
 call write_inopt(FLD_opt,'do FLD','Do FLD? (1) yes (0) no',iunit)

end subroutine write_options_cooling_stamatellos

subroutine read_options_cooling_stamatellos(name,valstring,imatch,igotallstam,ierr)
 use io, only:warning,fatal
 use eos_stamatellos, only: eos_file,doFLD
 character(len=*), intent(in)  :: name,valstring
 logical,          intent(out) :: imatch,igotallstam
 integer,          intent(out) :: ierr
 integer, save :: ngot = 0

 imatch  = .true.
 igotallstam = .false. ! cooling options are compulsory
 select case(trim(name))
 case('Lstar')
    read(valstring,*,iostat=ierr) Lstar
    if (Lstar < 0.) call fatal('Lstar','Luminosity cannot be negative')
    ngot = ngot + 1
 case('OD method')
    read(valstring,*,iostat=ierr) od_method
    if (od_method < 1 .or. od_method > 4) then
       call fatal('cooling options','od_method must be 1, 2, 3 or 4',var='od_method',ival=od_method)
    endif
    ngot = ngot + 1
 case('EOS_file')
    read(valstring,*,iostat=ierr) eos_file
    ngot = ngot + 1
 case('do FLD')
    read(valstring,*,iostat=ierr) FLD_opt
    if (FLD_opt < 0) call fatal('FLD_opt','FLD option out of range')
    if (FLD_opt == 0) then
       doFLD = .false.
    elseif (FLD_opt == 1) then
       doFLD = .true.
    endif
    ngot = ngot + 1
 case default
    imatch = .false.
 end select

 if (ngot >= 4) igotallstam = .true.

end subroutine read_options_cooling_stamatellos

end module cooling_stamatellos

