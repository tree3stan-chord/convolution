! impulse_response.f90
! Impulse response generation for different reverb types

module impulse_response
    use constants
    implicit none
    private
    
    ! Public procedures
    public :: generate_ir, apply_ir_parameters, get_ir_type_from_string
    
contains
    
    ! Main IR generation routine
    subroutine generate_ir(ir, ir_length, room_size, decay_time, pre_delay, &
                          damping, diffusion, sample_rate, ir_type)
        real(dp), dimension(:), intent(out) :: ir
        integer, intent(out) :: ir_length
        real(dp), intent(in) :: room_size, decay_time, pre_delay
        real(dp), intent(in) :: damping, diffusion
        integer, intent(in) :: sample_rate
        integer, intent(in) :: ir_type
        
        ! Initialize IR to zeros
        ir = 0.0_dp
        
        ! Calculate IR length based on decay time
        ir_length = min(int(decay_time * sample_rate), MAX_IR_SIZE)
        
        ! Generate base IR based on type
        select case(ir_type)
            case(IR_TYPE_HALL)
                call generate_hall_ir(ir, ir_length, room_size, decay_time, &
                                     pre_delay, damping, diffusion, sample_rate)
            case(IR_TYPE_CATHEDRAL)
                call generate_cathedral_ir(ir, ir_length, room_size, decay_time, &
                                          pre_delay, damping, diffusion, sample_rate)
            case(IR_TYPE_ROOM)
                call generate_room_ir(ir, ir_length, room_size, decay_time, &
                                     pre_delay, damping, diffusion, sample_rate)
            case(IR_TYPE_PLATE)
                call generate_plate_ir(ir, ir_length, room_size, decay_time, &
                                      pre_delay, damping, diffusion, sample_rate)
            case(IR_TYPE_SPRING)
                call generate_spring_ir(ir, ir_length, room_size, decay_time, &
                                       pre_delay, damping, diffusion, sample_rate)
            case default
                call generate_hall_ir(ir, ir_length, room_size, decay_time, &
                                     pre_delay, damping, diffusion, sample_rate)
        end select
        
        ! Normalize the impulse response
        call normalize_ir(ir, ir_length)
        
    end subroutine generate_ir
    
    ! Generate concert hall impulse response
    subroutine generate_hall_ir(ir, ir_length, room_size, decay_time, &
                                pre_delay, damping, diffusion, sample_rate)
        real(dp), dimension(:), intent(inout) :: ir
        integer, intent(in) :: ir_length
        real(dp), intent(in) :: room_size, decay_time, pre_delay
        real(dp), intent(in) :: damping, diffusion
        integer, intent(in) :: sample_rate
        
        integer :: i, j, num_reflections
        real(dp) :: t, amplitude, delay, decay_rate
        real(dp) :: reflection_density, freq_response
        integer :: pre_delay_samples
        
        pre_delay_samples = int(pre_delay * sample_rate / 1000.0_dp)
        decay_rate = 3.0_dp / decay_time  ! -60dB decay
        
        ! Early reflections pattern for hall
        call generate_early_reflections(ir, ir_length, pre_delay_samples, &
                                       room_size, sample_rate, 1.2_dp)
        
        ! Late reflections with hall characteristics
        reflection_density = 0.02_dp + room_size * 0.001_dp
        num_reflections = int(reflection_density * ir_length)
        
        do i = 1, num_reflections
            ! Random delay with hall-specific distribution
            delay = pre_delay_samples + &
                   (rand() ** 0.7_dp) * (ir_length - pre_delay_samples)
            j = min(int(delay), ir_length)
            
            if (j > 0 .and. j <= ir_length) then
                t = delay / real(sample_rate, dp)
                amplitude = exp(-decay_rate * t)
                
                ! Frequency-dependent damping for hall
                freq_response = 1.0_dp - damping * 0.01_dp * (1.0_dp - exp(-t))
                amplitude = amplitude * freq_response
                
                ! Add reflection with diffusion
                ir(j) = ir(j) + amplitude * (2.0_dp * rand() - 1.0_dp) * &
                        (0.3_dp + 0.7_dp * diffusion / 100.0_dp)
            end if
        end do
        
        ! Apply hall-specific coloration
        call apply_hall_coloration(ir, ir_length, sample_rate)
        
    end subroutine generate_hall_ir
    
    ! Generate cathedral impulse response
    subroutine generate_cathedral_ir(ir, ir_length, room_size, decay_time, &
                                    pre_delay, damping, diffusion, sample_rate)
        real(dp), dimension(:), intent(inout) :: ir
        integer, intent(in) :: ir_length
        real(dp), intent(in) :: room_size, decay_time, pre_delay
        real(dp), intent(in) :: damping, diffusion
        integer, intent(in) :: sample_rate
        
        integer :: i, j, num_reflections
        real(dp) :: t, amplitude, delay, decay_rate
        real(dp) :: reflection_density
        integer :: pre_delay_samples
        
        pre_delay_samples = int(pre_delay * sample_rate / 1000.0_dp)
        decay_rate = 2.5_dp / decay_time  ! Slower decay for cathedral
        
        ! Sparse early reflections for cathedral
        call generate_early_reflections(ir, ir_length, pre_delay_samples, &
                                       room_size, sample_rate, 2.0_dp)
        
        ! Dense late reflections
        reflection_density = 0.03_dp + room_size * 0.002_dp
        num_reflections = int(reflection_density * ir_length * 1.5_dp)
        
        do i = 1, num_reflections
            delay = pre_delay_samples + rand() * (ir_length - pre_delay_samples)
            j = min(int(delay), ir_length)
            
            if (j > 0 .and. j <= ir_length) then
                t = delay / real(sample_rate, dp)
                amplitude = exp(-decay_rate * t)
                
                ! Strong low frequency emphasis
                if (mod(i, 3) == 0) then
                    amplitude = amplitude * 1.3_dp
                end if
                
                ir(j) = ir(j) + amplitude * (2.0_dp * rand() - 1.0_dp) * &
                        (0.2_dp + 0.8_dp * diffusion / 100.0_dp)
            end if
        end do
        
        ! Apply cathedral-specific coloration
        call apply_cathedral_coloration(ir, ir_length, sample_rate)
        
    end subroutine generate_cathedral_ir
    
    ! Generate small room impulse response
    subroutine generate_room_ir(ir, ir_length, room_size, decay_time, &
                               pre_delay, damping, diffusion, sample_rate)
        real(dp), dimension(:), intent(inout) :: ir
        integer, intent(in) :: ir_length
        real(dp), intent(in) :: room_size, decay_time, pre_delay
        real(dp), intent(in) :: damping, diffusion
        integer, intent(in) :: sample_rate
        
        integer :: i, j, num_reflections
        real(dp) :: t, amplitude, delay, decay_rate
        integer :: pre_delay_samples
        
        pre_delay_samples = int(pre_delay * sample_rate / 1000.0_dp)
        decay_rate = 4.0_dp / decay_time  ! Faster decay for small room
        
        ! Prominent early reflections for room
        call generate_early_reflections(ir, ir_length, pre_delay_samples, &
                                       room_size, sample_rate, 0.5_dp)
        
        ! Moderate density late reflections
        num_reflections = int(0.015_dp * ir_length)
        
        do i = 1, num_reflections
            delay = pre_delay_samples + rand() * (ir_length - pre_delay_samples)
            j = min(int(delay), ir_length)
            
            if (j > 0 .and. j <= ir_length) then
                t = delay / real(sample_rate, dp)
                amplitude = exp(-decay_rate * t)
                
                ! Apply damping
                amplitude = amplitude * (1.0_dp - damping * 0.01_dp * t)
                
                ir(j) = ir(j) + amplitude * (2.0_dp * rand() - 1.0_dp) * &
                        (0.4_dp + 0.6_dp * diffusion / 100.0_dp)
            end if
        end do
        
    end subroutine generate_room_ir
    
    ! Generate plate reverb impulse response
    subroutine generate_plate_ir(ir, ir_length, room_size, decay_time, &
                                pre_delay, damping, diffusion, sample_rate)
        real(dp), dimension(:), intent(inout) :: ir
        integer, intent(in) :: ir_length
        real(dp), intent(in) :: room_size, decay_time, pre_delay
        real(dp), intent(in) :: damping, diffusion
        integer, intent(in) :: sample_rate
        
        integer :: i, j, num_reflections
        real(dp) :: t, amplitude, delay, decay_rate
        real(dp) :: dispersion_factor
        integer :: pre_delay_samples
        
        pre_delay_samples = int(pre_delay * sample_rate / 1000.0_dp)
        decay_rate = 3.5_dp / decay_time
        
        ! Minimal early reflections for plate
        call generate_early_reflections(ir, ir_length, pre_delay_samples, &
                                       room_size, sample_rate, 0.3_dp)
        
        ! High density dispersive reflections
        num_reflections = int(0.04_dp * ir_length)
        
        do i = 1, num_reflections
            ! Dispersive delay pattern
            dispersion_factor = 1.0_dp + 0.1_dp * sin(real(i, dp) * 0.1_dp)
            delay = pre_delay_samples + &
                   (rand() * (ir_length - pre_delay_samples)) * dispersion_factor
            j = min(int(delay), ir_length)
            
            if (j > 0 .and. j <= ir_length) then
                t = delay / real(sample_rate, dp)
                amplitude = exp(-decay_rate * t)
                
                ! Metallic character
                amplitude = amplitude * (1.0_dp + 0.2_dp * sin(t * 1000.0_dp))
                
                ir(j) = ir(j) + amplitude * (2.0_dp * rand() - 1.0_dp) * &
                        (0.5_dp + 0.5_dp * diffusion / 100.0_dp)
            end if
        end do
        
        ! Apply plate-specific coloration
        call apply_plate_coloration(ir, ir_length, sample_rate)
        
    end subroutine generate_plate_ir
    
    ! Generate spring reverb impulse response
    subroutine generate_spring_ir(ir, ir_length, room_size, decay_time, &
                                 pre_delay, damping, diffusion, sample_rate)
        real(dp), dimension(:), intent(inout) :: ir
        integer, intent(in) :: ir_length
        real(dp), intent(in) :: room_size, decay_time, pre_delay
        real(dp), intent(in) :: damping, diffusion
        integer, intent(in) :: sample_rate
        
        integer :: i, j, spring_delay
        real(dp) :: t, amplitude, decay_rate
        real(dp) :: spring_freq, chirp_rate
        integer :: pre_delay_samples
        
        pre_delay_samples = int(pre_delay * sample_rate / 1000.0_dp)
        decay_rate = 4.0_dp / decay_time
        
        ! Spring characteristic frequencies
        spring_freq = 2.0_dp + room_size * 0.05_dp
        chirp_rate = 0.001_dp
        
        ! Generate dispersive spring reflections
        do i = 1, ir_length - pre_delay_samples
            j = i + pre_delay_samples
            t = real(i, dp) / real(sample_rate, dp)
            
            ! Exponential decay
            amplitude = exp(-decay_rate * t)
            
            ! Spring dispersion (chirp effect)
            spring_delay = int(sin(spring_freq * t + chirp_rate * t * t) * 5.0_dp)
            
            if (j + spring_delay > 0 .and. j + spring_delay <= ir_length) then
                ! Add dispersed reflection
                ir(j + spring_delay) = ir(j + spring_delay) + &
                                      amplitude * sin(100.0_dp * t) * &
                                      (0.3_dp + 0.7_dp * diffusion / 100.0_dp)
            end if
            
            ! Add direct component with damping
            if (mod(i, 7) == 0) then
                ir(j) = ir(j) + amplitude * 0.5_dp * &
                        (1.0_dp - damping * 0.01_dp)
            end if
        end do
        
    end subroutine generate_spring_ir
    
    ! Generate early reflections pattern
    subroutine generate_early_reflections(ir, ir_length, pre_delay_samples, &
                                         room_size, sample_rate, spacing_factor)
        real(dp), dimension(:), intent(inout) :: ir
        integer, intent(in) :: ir_length, pre_delay_samples, sample_rate
        real(dp), intent(in) :: room_size, spacing_factor
        
        integer :: i, j, num_early
        real(dp) :: delay, amplitude
        
        ! Number of early reflections based on room size
        num_early = min(20, int(5 + room_size * 0.15_dp))
        
        do i = 1, num_early
            ! Logarithmic spacing of early reflections
            delay = pre_delay_samples + &
                   log(real(i, dp)) * sample_rate * 0.005_dp * spacing_factor
            j = min(int(delay), ir_length)
            
            if (j > 0 .and. j <= ir_length) then
                amplitude = 1.0_dp / real(i, dp) ** 0.7_dp
                ir(j) = ir(j) + amplitude * (2.0_dp * rand() - 1.0_dp)
            end if
        end do
        
    end subroutine generate_early_reflections
    
    ! Apply frequency coloration for hall
    subroutine apply_hall_coloration(ir, ir_length, sample_rate)
        real(dp), dimension(:), intent(inout) :: ir
        integer, intent(in) :: ir_length, sample_rate
        
        integer :: i
        real(dp) :: freq, gain
        
        ! Simple frequency shaping
        do i = 1, ir_length
            freq = real(i, dp) / real(ir_length, dp) * real(sample_rate, dp) / 2.0_dp
            
            ! Boost low-mids, slight high rolloff
            gain = 1.0_dp + 0.3_dp * exp(-(freq - 250.0_dp)**2 / 10000.0_dp)
            gain = gain * exp(-freq / 8000.0_dp)
            
            if (i <= ir_length) ir(i) = ir(i) * gain
        end do
        
    end subroutine apply_hall_coloration
    
    ! Apply frequency coloration for cathedral
    subroutine apply_cathedral_coloration(ir, ir_length, sample_rate)
        real(dp), dimension(:), intent(inout) :: ir
        integer, intent(in) :: ir_length, sample_rate
        
        integer :: i
        real(dp) :: freq, gain
        
        do i = 1, ir_length
            freq = real(i, dp) / real(ir_length, dp) * real(sample_rate, dp) / 2.0_dp
            
            ! Strong low frequency emphasis
            gain = 1.0_dp + 0.5_dp * exp(-freq / 500.0_dp)
            
            if (i <= ir_length) ir(i) = ir(i) * gain
        end do
        
    end subroutine apply_cathedral_coloration
    
    ! Apply frequency coloration for plate
    subroutine apply_plate_coloration(ir, ir_length, sample_rate)
        real(dp), dimension(:), intent(inout) :: ir
        integer, intent(in) :: ir_length, sample_rate
        
        integer :: i
        real(dp) :: freq, gain
        
        do i = 1, ir_length
            freq = real(i, dp) / real(ir_length, dp) * real(sample_rate, dp) / 2.0_dp
            
            ! Metallic character - boost around 1-3kHz
            gain = 1.0_dp + 0.4_dp * exp(-(freq - 2000.0_dp)**2 / 500000.0_dp)
            
            if (i <= ir_length) ir(i) = ir(i) * gain
        end do
        
    end subroutine apply_plate_coloration
    
    ! Normalize impulse response
    subroutine normalize_ir(ir, ir_length)
        real(dp), dimension(:), intent(inout) :: ir
        integer, intent(in) :: ir_length
        
        real(dp) :: max_val, rms_val
        integer :: i
        
        ! Find maximum value
        max_val = 0.0_dp
        rms_val = 0.0_dp
        
        do i = 1, ir_length
            max_val = max(max_val, abs(ir(i)))
            rms_val = rms_val + ir(i) * ir(i)
        end do
        
        rms_val = sqrt(rms_val / real(ir_length, dp))
        
        ! Normalize to prevent clipping
        if (max_val > 0.0_dp) then
            ir(1:ir_length) = ir(1:ir_length) / max_val * 0.9_dp
        end if
        
    end subroutine normalize_ir
    
    ! Apply additional IR parameters
    subroutine apply_ir_parameters(ir, ir_length, low_freq, early_reflections)
        real(dp), dimension(:), intent(inout) :: ir
        integer, intent(in) :: ir_length
        real(dp), intent(in) :: low_freq, early_reflections
        
        ! Apply low frequency adjustment
        if (low_freq /= 50.0_dp) then
            call apply_low_freq_adjustment(ir, ir_length, low_freq)
        end if
        
        ! Adjust early reflections level
        if (early_reflections /= 50.0_dp) then
            call adjust_early_reflections(ir, ir_length, early_reflections)
        end if
        
    end subroutine apply_ir_parameters
    
    ! Apply low frequency adjustment
    subroutine apply_low_freq_adjustment(ir, ir_length, low_freq_amount)
        real(dp), dimension(:), intent(inout) :: ir
        integer, intent(in) :: ir_length
        real(dp), intent(in) :: low_freq_amount
        
        integer :: i
        real(dp) :: gain
        
        ! Simple low frequency boost/cut
        gain = 0.5_dp + low_freq_amount / 100.0_dp
        
        ! Apply to first part of IR (affects low frequencies more)
        do i = 1, min(ir_length / 4, ir_length)
            ir(i) = ir(i) * (1.0_dp + (gain - 1.0_dp) * (1.0_dp - real(i, dp) / real(ir_length / 4, dp)))
        end do
        
    end subroutine apply_low_freq_adjustment
    
    ! Adjust early reflections level
    subroutine adjust_early_reflections(ir, ir_length, early_level)
        real(dp), dimension(:), intent(inout) :: ir
        integer, intent(in) :: ir_length
        real(dp), intent(in) :: early_level
        
        integer :: i, early_end
        real(dp) :: gain
        
        gain = early_level / 50.0_dp
        early_end = min(ir_length / 10, ir_length)
        
        do i = 1, early_end
            ir(i) = ir(i) * gain
        end do
        
    end subroutine adjust_early_reflections
    
    ! Convert IR type string to integer
    function get_ir_type_from_string(ir_type_str) result(ir_type)
        character(len=*), intent(in) :: ir_type_str
        integer :: ir_type
        
        select case(trim(adjustl(ir_type_str)))
            case('hall')
                ir_type = IR_TYPE_HALL
            case('cathedral')
                ir_type = IR_TYPE_CATHEDRAL
            case('room')
                ir_type = IR_TYPE_ROOM
            case('plate')
                ir_type = IR_TYPE_PLATE
            case('spring')
                ir_type = IR_TYPE_SPRING
            case default
                ir_type = IR_TYPE_HALL
        end select
        
    end function get_ir_type_from_string
    
end module impulse_response