! convolution_reverb.f90
! Main convolution reverb engine implementation in Fortran

module convolution_engine
    use constants
    use fft_module
    use impulse_response
    implicit none
    
    ! Module variables for state management
    real(dp), dimension(MAX_BUFFER_SIZE) :: input_buffer
    real(dp), dimension(MAX_BUFFER_SIZE) :: output_buffer
    real(dp), dimension(MAX_IR_SIZE) :: current_ir
    complex(dp), dimension(:), allocatable :: fft_buffer
    complex(dp), dimension(:), allocatable :: ir_fft
    
    ! Overlap-save buffers for real-time processing
    real(dp), dimension(:), allocatable :: overlap_buffer
    integer :: overlap_size = 0
    integer :: fft_size_current = 0
    
    ! Current parameters
    real(dp) :: current_room_size = 50.0_dp
    real(dp) :: current_decay_time = 2.5_dp
    real(dp) :: current_pre_delay = 20.0_dp
    real(dp) :: current_damping = 50.0_dp
    real(dp) :: current_low_freq = 50.0_dp
    real(dp) :: current_diffusion = 80.0_dp
    real(dp) :: current_mix = 30.0_dp
    real(dp) :: current_early_reflections = 50.0_dp
    integer :: current_ir_type = IR_TYPE_HALL
    integer :: current_sample_rate = 48000
    integer :: current_ir_length = 0
    logical :: ir_needs_update = .true.
    logical :: engine_initialized = .false.
    
contains
    
    ! Initialize the convolution engine
    subroutine init_convolution_engine(sample_rate) bind(C, name='init_convolution_engine_')
        integer, intent(in) :: sample_rate
        
        current_sample_rate = sample_rate
        
        ! Allocate FFT buffers
        if (allocated(fft_buffer)) deallocate(fft_buffer)
        if (allocated(ir_fft)) deallocate(ir_fft)
        if (allocated(overlap_buffer)) deallocate(overlap_buffer)
        
        ! Determine FFT size for real-time processing
        fft_size_current = next_power_of_2(BLOCK_SIZE * 4)
        
        allocate(fft_buffer(fft_size_current))
        allocate(ir_fft(fft_size_current))
        allocate(overlap_buffer(fft_size_current))
        
        ! Initialize buffers
        input_buffer = 0.0_dp
        output_buffer = 0.0_dp
        current_ir = 0.0_dp
        overlap_buffer = 0.0_dp
        
        ! Force IR regeneration
        ir_needs_update = .true.
        engine_initialized = .true.
        
        print *, "Convolution engine initialized with sample rate:", sample_rate
        
    end subroutine init_convolution_engine
    
    ! Set parameter by ID (for C interface)
    subroutine set_param_float(param_id, value) bind(C, name='set_param_float_')
        integer, intent(in) :: param_id
        real(sp), intent(in) :: value
        
        select case(param_id)
            case(0)  ! room_size
                current_room_size = real(value, dp)
                ir_needs_update = .true.
            case(1)  ! decay_time
                current_decay_time = real(value, dp)
                ir_needs_update = .true.
            case(2)  ! pre_delay
                current_pre_delay = real(value, dp)
                ir_needs_update = .true.
            case(3)  ! damping
                current_damping = real(value, dp)
                ir_needs_update = .true.
            case(4)  ! low_freq
                current_low_freq = real(value, dp)
            case(5)  ! diffusion
                current_diffusion = real(value, dp)
                ir_needs_update = .true.
            case(6)  ! mix
                current_mix = real(value, dp)
            case(7)  ! early_reflections
                current_early_reflections = real(value, dp)
        end select
        
    end subroutine set_param_float
    
    ! Set parameter by name (C interface with fixed length)
    subroutine set_parameter(param_name, value, name_len) bind(C, name='set_parameter_')
        use iso_c_binding
        character(kind=c_char), dimension(*), intent(in) :: param_name
        real(c_double), intent(in) :: value
        integer(c_int), intent(in) :: name_len
        
        character(len=32) :: param_str
        integer :: i
        
        ! Convert C string to Fortran string
        param_str = ' '
        do i = 1, min(name_len, 32)
            param_str(i:i) = param_name(i)
        end do
        
        select case(trim(adjustl(param_str)))
            case('roomSize')
                current_room_size = value
                ir_needs_update = .true.
            case('decayTime')
                current_decay_time = value
                ir_needs_update = .true.
            case('preDelay')
                current_pre_delay = value
                ir_needs_update = .true.
            case('damping')
                current_damping = value
                ir_needs_update = .true.
            case('lowFreq')
                current_low_freq = value
            case('diffusion')
                current_diffusion = value
                ir_needs_update = .true.
            case('mix')
                current_mix = value
            case('earlyReflections')
                current_early_reflections = value
        end select
        
    end subroutine set_parameter
    
    ! Set impulse response type (C interface with fixed length)
    subroutine set_ir_type(ir_type_str, type_len) bind(C, name='set_ir_type_')
        use iso_c_binding
        character(kind=c_char), dimension(*), intent(in) :: ir_type_str
        integer(c_int), intent(in) :: type_len
        
        character(len=20) :: type_str
        integer :: i
        
        ! Convert C string to Fortran string
        type_str = ' '
        do i = 1, min(type_len, 20)
            type_str(i:i) = ir_type_str(i)
        end do
        
        current_ir_type = get_ir_type_from_string(type_str)
        ir_needs_update = .true.
        
    end subroutine set_ir_type
    
    ! Update impulse response if needed
    subroutine update_ir_if_needed()
        integer :: i
        
        if (.not. ir_needs_update) return
        
        ! Generate new impulse response
        call generate_ir(current_ir, current_ir_length, &
                        current_room_size, current_decay_time, current_pre_delay, &
                        current_damping, current_diffusion, current_sample_rate, &
                        current_ir_type)
        
        ! Apply additional parameters
        call apply_ir_parameters(current_ir, current_ir_length, &
                               current_low_freq, current_early_reflections)
        
        ! Pre-compute IR FFT for fast convolution
        if (current_ir_length > 0) then
            ir_fft = cmplx(0.0_dp, 0.0_dp, dp)
            do i = 1, min(current_ir_length, fft_size_current)
                ir_fft(i) = cmplx(current_ir(i), 0.0_dp, dp)
            end do
            call fft(ir_fft, fft_size_current, .false.)
        end if
        
        ir_needs_update = .false.
        
    end subroutine update_ir_if_needed
    
    ! Main convolution processing function
    subroutine process_convolution(input, output, num_samples) bind(C, name='process_convolution_')
        real(dp), dimension(num_samples), intent(in) :: input
        real(dp), dimension(num_samples), intent(out) :: output
        integer, intent(in) :: num_samples
        
        integer :: i
        real(dp) :: dry_gain, wet_gain
        
        if (.not. engine_initialized) then
            output = input
            return
        end if
        
        ! Update IR if needed
        call update_ir_if_needed()
        
        ! Calculate mix gains
        dry_gain = 1.0_dp - current_mix / 100.0_dp
        wet_gain = current_mix / 100.0_dp
        
        ! Process in blocks for better cache performance
        if (num_samples <= BLOCK_SIZE) then
            ! Small buffer - use direct convolution
            call convolve_direct(input, num_samples, output, dry_gain, wet_gain)
        else
            ! Large buffer - use FFT convolution
            call convolve_fft(input, num_samples, output, dry_gain, wet_gain)
        end if
        
    end subroutine process_convolution
    
    ! Direct convolution for small buffers
    subroutine convolve_direct(input, n_samples, output, dry_gain, wet_gain)
        real(dp), dimension(:), intent(in) :: input
        integer, intent(in) :: n_samples
        real(dp), dimension(:), intent(out) :: output
        real(dp), intent(in) :: dry_gain, wet_gain
        
        integer :: i, j
        real(dp) :: wet_sample
        
        ! Initialize with dry signal
        do i = 1, n_samples
            output(i) = dry_gain * input(i)
        end do
        
        ! Add convolved wet signal
        do i = 1, n_samples
            wet_sample = 0.0_dp
            do j = 1, min(i, current_ir_length)
                if (i - j + 1 > 0) then
                    wet_sample = wet_sample + input(i - j + 1) * current_ir(j)
                end if
            end do
            output(i) = output(i) + wet_gain * wet_sample
        end do
        
    end subroutine convolve_direct
    
    ! FFT convolution for larger buffers
    subroutine convolve_fft(input, n_samples, output, dry_gain, wet_gain)
        real(dp), dimension(:), intent(in) :: input
        integer, intent(in) :: n_samples
        real(dp), dimension(:), intent(out) :: output
        real(dp), intent(in) :: dry_gain, wet_gain
        
        real(dp), dimension(:), allocatable :: wet_output
        integer :: processed, i
        
        allocate(wet_output(n_samples + current_ir_length))
        
        ! Use FFT convolution
        call fft_convolve(input, n_samples, current_ir, current_ir_length, &
                         wet_output, processed)
        
        ! Mix dry and wet signals
        do i = 1, n_samples
            output(i) = dry_gain * input(i) + wet_gain * wet_output(i)
        end do
        
        deallocate(wet_output)
        
    end subroutine convolve_fft
    
    ! Get initialization status
    function is_initialized() bind(C, name='is_initialized_') result(status)
        integer :: status
        
        if (engine_initialized) then
            status = 1
        else
            status = 0
        end if
        
    end function is_initialized
    
    ! Get current sample rate
    function get_sample_rate() bind(C, name='get_sample_rate_') result(rate)
        integer :: rate
        
        rate = current_sample_rate
        
    end function get_sample_rate
    
    ! Get version string
    function get_version() bind(C, name='get_version_') result(version_ptr)
        use iso_c_binding
        type(c_ptr) :: version_ptr
        character(len=10), target, save :: version = "1.0.0"
        
        version_ptr = c_loc(version)
        
    end function get_version
    
    ! Cleanup routine
    subroutine cleanup_convolution_engine() bind(C, name='cleanup_convolution_engine_')
        
        if (allocated(fft_buffer)) deallocate(fft_buffer)
        if (allocated(ir_fft)) deallocate(ir_fft)
        if (allocated(overlap_buffer)) deallocate(overlap_buffer)
        
        engine_initialized = .false.
        
    end subroutine cleanup_convolution_engine
    
end module convolution_engine

! C-compatible wrapper for audio processing
subroutine process_audio_chunk(input_ptr, output_ptr, num_samples) bind(C, name='process_audio_chunk')
    use iso_c_binding
    use convolution_engine
    implicit none
    
    type(c_ptr), value :: input_ptr, output_ptr
    integer(c_int), value :: num_samples
    
    real(c_double), pointer :: input(:), output(:)
    
    call c_f_pointer(input_ptr, input, [num_samples])
    call c_f_pointer(output_ptr, output, [num_samples])
    
    call process_convolution(input, output, num_samples)
    
end subroutine process_audio_chunk