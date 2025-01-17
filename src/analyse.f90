module qcxms_analyse
  use common1
  use qcxms_iniqm, only: eqm
  use qcxms_info, only: qcstring
  use qcxms_utility, only: getspin
  use xtb_mctc_accuracy, only: wp
  use xtb_mctc_convert
  use xtb_mctc_symbols, only: toSymbol 
  implicit none

  contains


  subroutine analyse(iprog,nuc,iat,axyz,list,etemp,ip, &
      natf,ipok,icoll,isec,metal3d,ECP)
    
    integer :: nuc  
    integer :: iprog 
    integer :: list(nuc)
    integer :: iat (nuc)
    integer :: icoll,isec
    integer :: natf(10)
    integer :: i,j,k
    integer :: nfrag
    integer :: iok,progi,itry,useprog(4)  
    integer :: counter
    integer :: isave,jsave,ksave,gsave
    integer :: iatf(nuc,10)
    integer :: idum(nuc,10)
    integer :: neutfspin,ionfspin !fragment spin (for metals etc.)
    integer :: fiter !Number of spin iterations 
    integer :: sp(3),sn(3),sn0,sp0
!    integer, intent(in) :: gfnver
    integer :: nb,nel
    integer :: io_xyz 
  
    real(wp) :: axyz(3,nuc)
    real(wp) :: ip(10),etemp
    real(wp) :: xyzf(3,nuc,10)
    real(wp) :: dum (3,nuc,10)
    real(wp) :: z,en,ep,cema(3,10),rf(10*(10+1)/2)
    real(wp) :: t2,t1,w2,w1
    real(wp) :: gsen(3),gsep(3)
    real(wp) :: dsave
!    real(wp) :: ipshift,eashift
  
    character(len=80) :: fname
    character(len=20) :: line, line2
    
    logical :: ipok
    logical :: metal3d,ECP
    logical :: boolm !if fragment has metal
    logical :: ipcalc
    logical :: spec_calc = .false.
   

    ! timings
    t1 = 0.0_wp
    t2 = 0.0_wp
    w1 = 0.0_wp
    w2 = 0.0_wp

    write(*,'('' computing average fragment structures ...'')')
    
    ipok=.true.
    xyzf = 0
    iatf = 0
    nfrag=maxval(list)
    do i=1,nuc
       j=list(i)
       xyzf(1:3,i,j)=axyz(1:3,i)
       iatf(    i,j)=iat(    i)
    enddo   
    dum  = xyzf
    idum = iatf
    
    xyzf = 0
    iatf = 0 
    do i=1,nfrag
       k=0
       do j=1,nuc
          if(idum(j,i) /= 0)then
             k=k+1
             xyzf(1:3,k,i)=dum(1:3,j,i)     
             iatf(    k,i)=idum(   j,i)     
          endif
       enddo   
       natf(i)=k
    enddo    
    
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !write fragments with average geometries      
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    ! CID
    if(method == 3.or.method == 4)then
       do i=1,nfrag
          cema(1:3,i) = 0
          z           = 0
  
          if (icoll < 10) write(fname,'(i1,''.'',i1,''.'',i1,''.xyz'')') icoll, isec, i
          if (icoll >= 10) write(fname,'(i2,''.'',i1,''.'',i1,''.xyz'')') icoll, isec, i

          open (file = fname, newunit = io_xyz)
!          open (unit=42, file = fname)
  
          write(io_xyz,*) natf(i)
          write(io_xyz,*)
  
          do j=1,natf(i)
             write(io_xyz,'(a2,5x,3F18.8)') toSymbol(iatf(j,i)), xyzf(1:3,j,i) * autoaa 
             cema(1:3,i) = cema(1:3,i) + xyzf(1:3,j,i) * iatf(j,i)
             z = z + iatf(j,i)
          enddo
          close(io_xyz)
          cema(1:3,i) = cema(1:3,i) / z
       enddo   

    ! EI/DEA
    else
       do i=1,nfrag
          cema(1:3,i) = 0
          z           = 0
  
          write(fname,'(i1,''.'',i1,''.xyz'')') isec, i

          open (file = fname, newunit = io_xyz)
!          open (unit=42, file = fname)

          write(io_xyz,*)natf(i)
          write(io_xyz,*)

          do j=1,natf(i)
             write(io_xyz,'(a2,5x,3F18.8)') toSymbol(iatf(j,i)), xyzf(1:3,j,i) * autoaa 
             cema(1:3,i) = cema(1:3,i) + xyzf(1:3,j,i) * iatf(j,i)
             z = z + iatf(j,i)
          enddo

          close(io_xyz)

          cema(1:3,i) = cema(1:3,i) / z
       enddo 
    endif

    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    
    k=0
    do i=1,nfrag
       do j=1,i
          k=k+1
          rf(k)=0
          if(i /= j)then
             rf(k)=sqrt((cema(1,i)-cema(1,j))**2 + &
                        (cema(2,i)-cema(2,j))**2 + &
                        (cema(3,i)-cema(3,j))**2) * autoaa
          endif
       enddo
    enddo   
    
    if(nfrag > 1) then
      write(*,'(2x,a)') 'inter fragment distances (Angst.)'
      call print_matrix(rf,nfrag,0)
    else
      return
    endif
   
    ! PBE0/SVx for semi, SV(P) is too costly then but negligible in a DFT
    ! save original run parameters
    isave=bas
    jsave=func
    ksave=ihamilt
    gsave=gfnver   !save gfnver

    ipcalc= .False.

    ! save etemp for XTB !THIS IS NOT ETEMP! BUT AVERAGE TEMP OF FRAGMENT!
    dsave=eTemp

    if(method  ==  2) then
               bas = 7          !ma-def2-TZVP
       if(ecp) bas = 11         !def2-TZVP
    else
               bas = 3           !SV(P)
       if(ecp) bas = 9           !def2-SV(P)
    endif
  
    itry = 1

    ! If IP calculation fails, try other QC codes,
    ! especially XTB (build-in) and ORCA (free)

    ! MOPAC, XTB, XTB2,ORCA
    if (iprog == 1) then
       useprog(1) = iprog
       useprog(2) = 7   
       useprog(3) = 8   
       useprog(4) = 3  

    ! TM, ORCA, XTB, XTB2
    elseif (iprog == 2) then
       useprog(1) = iprog
       useprog(2) = 3  
       useprog(3) = 7   
       useprog(4) = 8   

    ! ORCA, TMOL, XTB, XTB2
    elseif (iprog == 3) then
       useprog(1) = iprog
       useprog(2) = 2   
       useprog(3) = 7   
       useprog(4) = 8  
  
    ! MSINDO, XTB, XTB2, ORCA
    elseif (iprog == 4) then
       useprog(1) = iprog
       useprog(2) = 7   
       useprog(3) = 8   
       useprog(4) = 3   
  
    ! MNDO ,XTB, XTB2, ORCA
    elseif (iprog == 5) then
       useprog(1) = iprog
       useprog(2) = 7   
       useprog(3) = 8   
       useprog(4) = 3   
  
    ! XTB, XTB, XTB2, ORCA
    elseif (iprog == 7) then
       useprog(1) = iprog
       useprog(2) = iprog
       useprog(3) = 8
       useprog(4) = 3
  
    ! XTB2, XTB, ORCA
     elseif (iprog == 8) then
        useprog(1) = iprog
        useprog(2) = iprog
        useprog(3) = 7
        useprog(4) = 3
     endif
    
    call timing(t1,w1)
  
   !!!!!!!!!!!!!!!!!!!!!!!! 
!     999  progi=useprog(itry)
   !!!!!!!!!!!!!!!!!!!!!!!! 
   do 
      progi=useprog(itry)
    
      ! defaults for the IP calc. (PM6 for MOPAC, OM2 for MNDO99 if ORCA fails)      
      if (progi == 1) ihamilt = 4
      if (progi == 5) ihamilt = 6
      
      ! If IP program is XTB
      if (progi == 7) then
         etemp  = 300.0d0
         ipcalc = .True.
         gfnver = 1
  
      elseif (progi == 8) then
         etemp  = 300.0d0
         ipcalc = .True.
         gfnver = 3
      endif
      
      call qcstring(progi,line,line2) 
  
      if (method ==  2.or.method == 4) then
         write(*,'(/,'' computing EAs with '',(a14),'' at (K) '',f7.0)')trim(line2),dsave
      else
         write(*,'(/,'' computing IPs with '',(a14),'' at (K) '',f7.0)')trim(line2),dsave
      endif
  
      ip  = 0
      iok = 0
      counter = 0
      
      !      write(*,*) '* IP/EA will be calculated 
      !     .with respect to metal fragment multiplicities *'
      sn = 0
      sp = 0
  
      do i = 1,nfrag
         gsen  = 0.0d0
         gsep  = 0.0d0
         boolm = .False.
  
      ! if metal3d is true, check if fragment i has a metal atom.
         if (metal3d) then
            do k = 1, natf(i)
               if (iatf(k,i) <= 30.and.iatf(k,i) >= 22) then
                  boolm = .True.
               endif
            enddo
         endif
      
         if (boolm) then
            fiter = 3
      !     FIND SPIN FOR ION AND NEUTRAL of metal              
            call getspin(natf(i),iatf(1,i),0,neutfspin)
            if (method ==  2 .or.method == 4) then
               call getspin(natf(i),iatf(1,i),-1,ionfspin)
            else
               call getspin(natf(i),iatf(1,i),1,ionfspin)
            endif 
      
         else                   !NO METAL (DO ORDINARY CALC WITH -1 FOR SPIN)
      ! That means eqm (iniqm.f), will assign spin by itself.                  
            boolm = .False.
            fiter = 1
            neutfspin = -1
            ionfspin = -1                  
         endif
      
      ! MOPAC IP is unreliable for H and other atoms           
         if(progi == 1.and.natf(i) == 1)then
            if(method ==  2)stop 'MOPAC CANT BE USED FOR EA!'
            ip(i) =  valip(iatf(1,i))
            en    = 1.d-6
            ep    = ip(i) * evtoau 
            iok   = iok + 2
         else
            do k=1,fiter         !ITER OVER MULTIPLICITES
               if (k > 1 .and. boolm) then
                  neutfspin=neutfspin+2
                  ionfspin=ionfspin+2
               endif
  
      ! CALCULATE NEUTRAL (MCHARGE=0)
               call eqm(progi,natf(i),xyzf(1,1,i),&
                 iatf(1,i),0,neutfspin,etemp,.true.,iok,en,nel,nb,ECP,spec_calc)
      
  
               if(boolm)then
                  gsen(k) = en
                  sn(k)   = neutfspin
               endif
  
      ! CALCULATE ION 
               if(method ==  2.or.method == 4)then
      !     DEA (MCHARGE=-1)              
                  call eqm(progi,natf(i),xyzf(1,1,i),&
                  iatf(1,i),-1,ionfspin,etemp,.true.,iok,ep,nel,nb,ECP,spec_calc)
  
                  if (boolm)then
                     gsep(k) = ep
                     sp(k) = ionfspin
                  endif
  
               else
  
      !     OTHER (MCHARGE=+1)
                  call eqm(progi,natf(i),xyzf(1,1,i),&
                  iatf(1,i),1,ionfspin,etemp,.true.,iok,ep,nel,nb,ECP,spec_calc)
                  if(boolm)then
                     gsep(k) = ep
                     sp(k) = ionfspin
                  endif
               endif !ENDING DEA CHECK STATEMENT
  
               counter = counter+1 !used for the IOK CHECK
  
            enddo ! ENDING ITERATION OVER MULTIPLICITES
         endif   !ENDING IF STATEMENT WHICH STARTS BY MOPAC CHECK
      
      ! Select lowest values - to calculate vertical IP/EA from groundstate neutral to groundstate ion, in regards to spin multiplicity
         if(boolm) then
            en = minval(gsen)
            ep = minval(gsep)
      ! save neutral-ion (of metal) lowest energy spin
            sn0 = 0
            sp0 = 0
  
            do k=1,3
               if (gsen(k)  ==  en) then
                  sn0 = sn(k)              
               endif
               if (gsep(k)  ==  ep) then
                  sp0 = sp(k)
               endif
            enddo
         endif
      
         if (ep /= 0 .and. en /= 0) then
            ip(i) = (ep - en) * autoev
  
           !! SHIFT IP FOR XTB - is 0 anyways
           ! if (progi == 7.or. progi == 8 .or. progi == 9) then !!!XTB2 ?!?!?!
           !    if (method == 2.or.method == 4) then
           !       write(*,'(''EA SHIFT (eV): '',F8.4)')eashift* autoev
           !       ip(i) = ip(i) + (eashift * autoev) 
           !    else
           !       write(*,'(''IP SHIFT (eV): '',F8.4)')ipshift* autoev
           !       ip(i) = ip(i) - (ipshift * autoev) 
           !    endif
           ! endif
  
      ! THE SIGN OF EA IS OPPOSITE TO IP           
            if(method == 2 .or. method == 4) ip(i) = -1.0d0*ip(i)
      ! PRINT OUT
            if (boolm) then
               write(*,'('' fragment '',i2,'' E(N)='',F12.4,''  E(I)='',F12.4,5x,'' &
                    &       IP/EA(eV)='',F8.2,5x,'' Mult.:'',i2,'' (N) and '',i2,'' (I)'')') &
                    &       i,en,ep,ip(i),sn0,sp0
            else
               write(*,'('' fragment '',i2,'' E(N)='',F12.4,''  E(I)='',F12.4,5x,'' &
                    &       IP/EA(eV)='',F8.2)') i,en,ep,ip(i)
      ! ok ?           
            endif
      
            if (method == 2 .or. method == 4) then
      ! NOT SURE WHAT THE BOUNDARIES HERE SHOULD BE FOR EA??
      ! that is why they just have ridicilously high (abs) values.
               if (ip(i) > 20.0_wp .or. ip(i) < -25.0_wp) iok = iok - 2        
            else
               if (ip(i) < 0.0_wp  .or. ip(i) > 30.0_wp)  iok = iok - 2        
            endif
      
         endif
      enddo   
      
      ! if failed try another code      
      if (iok /= counter*2) then
         itry = itry + 1
         if (itry <= 3) then
            write(*,*) '* Try: ', itry, ' failed *'
            cycle
         else
      ! total failure, use Mpop in main                 
            ip(1:nfrag)=0
            ipok=.false.
            exit
         endif
      else
        exit ! finish all good
      endif   

    enddo
    
    ! restore original settings
    etemp   = dsave
    bas     = isave
    func    = jsave
    ihamilt = ksave
    gfnver  = gsave

    ipcalc  = .False.
    
    call timing(t2,w2)
    if(method == 2.or.method == 4)then
       write(*,'(/,'' wall time for EA (s)'',F10.1,/)')(w2-w1)
    else
       write(*,'(/,'' wall time for IP (s)'',F10.1,/)')(w2-w1)
    endif
    
    
  end subroutine analyse
    
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!       
    ! FUNCTION FOR ATOM IP (USED ONLY FOR MOPAC)
  function valip(i) result(get_ip)

    integer  :: i

    real(wp) :: ip(94), get_ip
    
    ip(1 )=-13.598
    ip(2 )=-24.587
    ip(3 )=-3.540   
    ip(4 )=-5.600
    ip(5 )=-8.298
    ip(6 )=-11.260
    ip(7 )=-14.534
    ip(8 )=-13.618
    ip(9 )=-17.423
    ip(10)=-21.565
    ip(11)=-3.091
    ip(12)=-4.280
    ip(13)=-5.986
    ip(14)=-8.152
    ip(15)=-10.487
    ip(16)=-10.360
    ip(17)=-12.968
    ip(18)=-15.760
    ip(19)=-2.786
    ip(20)=-3.744
    ip(21)=-9.450
    ip(22)=-10.495
    ip(23)=-10.370
    ip(24)=-10.642
    ip(25)=-13.017
    ip(26)=-14.805
    ip(27)=-14.821
    ip(28)=-13.820
    ip(29)=-14.100
    ip(30)=-4.664
    ip(31)=-5.999
    ip(32)=-7.899
    ip(33)=-9.789
    ip(34)=-9.752
    ip(35)=-11.814
    ip(36)=-14.000
    ip(37)=-2.664
    ip(38)=-3.703
    ip(39)=-7.173
    ip(40)=-8.740
    ip(41)=-10.261
    ip(42)=-11.921
    ip(43)=-12.59
    ip(44)=-14.214
    ip(45)=-15.333
    ip(46)=-8.337
    ip(47)=-17.401
    ip(48)=-4.686
    ip(49)=-5.786
    ip(50)=-7.344
    ip(51)=-8.608
    ip(52)=-9.010
    ip(53)=-10.451
    ip(54)=-12.130
    ip(55)=-2.544
    ip(56)=-3.333
    ip(57)=-7.826
    ip(58)=-7.594
    ip(59)=-4.944
    ip(60)=-4.879
    ip(61)=-4.813
    ip(62)=-4.754
    ip(63)=-4.615
    ip(64)=-7.915
    ip(65)=-4.617
    ip(66)=-4.566
    ip(67)=-4.520
    ip(68)=-4.487
    ip(69)=-4.441
    ip(70)=-4.378
    ip(71)=-5.428
    ip(72)=-8.419
    ip(73)=-10.786
    ip(74)=-12.293
    ip(75)=-13.053
    ip(76)=-15.450
    ip(77)=-17.779
    ip(78)=-19.695
    ip(79)=-21.567
    ip(80)=-5.521
    ip(81)=-6.108
    ip(82)=-7.417
    ip(83)=-7.286
    ip(84)=-8.417
    ip(85)=-10.7
    ip(86)=-10.748
    ip(87)=-2.637
    ip(88)=-3.412
    ip(89)=-6.97
    ip(90)=-9.951
    ip(91)=-8.09
    ip(92)=-9.115
    ip(93)=-9.243
    ip(94)=-6.324
    
    get_ip = -ip(i)
  
  end function valip

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

end module qcxms_analyse
