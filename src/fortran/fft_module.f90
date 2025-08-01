! fft_module.f90
! Fast Fourier Transform implementation for convolution

module fft_module
    use constants
    implicit none
    private
    
    ! Public procedures
    public :: fft, ifft, fft_real, next_power_of_2, fft_convolve
    
contains
    
    ! Complex FFT using Cooley-Tukey algorithm
    subroutine fft(x, n, inverse)
        complex(dp), dimension(n), intent(inout) :: x
        integer, intent(in) :: n
        logical, intent(in) :: inverse
        
        integer :: i, j, k, n1, n2, a
        real(dp) :: c, s, e, t1, t2
        complex(dp) :: t, w
        
        ! Check if n is power of 2
        if (iand(n, n-1) /= 0) then
            print *, "Error: FFT size must be power of 2"
            return
        end if
        
        ! Bit reversal
        j = 0
        n2 = n / 2
        do i = 1, n - 2
            n1 = n2
            do while (j >= n1)
                j = j - n1
                n1 = n1 / 2
            end do
            j = j + n1
            
            if (i < j) then
                t = x(i + 1)
                x(i + 1) = x(j + 1)
                x(j + 1) = t
            end if
        end do
        
        ! FFT computation
        n1 = 0
        n2 = 1
        
        do i = 1, int(log(real(n))/log(2.0))
            n1 = n2
            n2 = n2 + n2
            e = -two_pi / n2
            if (inverse) e = -e
            a = 0
            
            do j = 1, n1
                c = cos(a * e)
                s = sin(a * e)
                a = a + 1
                
                do k = j, n, n2
                    t = cmplx(c * real(x(k + n1)), s * aimag(x(k + n1)), dp) + &
                        cmplx(-s * real(x(k + n1)), c * aimag(x(k + n1)), dp) * cmplx(0.0_dp, 1.0_dp, dp)
                    x(k + n1) = x(k) - t
                    x(k) = x(k) + t
                end do
            end do
        end do
        
        ! Normalize for inverse transform
        if (inverse) then
            do i = 1, n
                x(i) = x(i) / real(n, dp)
            end do
        end if
    end subroutine fft
    
    ! Inverse FFT wrapper
    subroutine ifft(x, n)
        complex(dp), dimension(n), intent(inout) :: x
        integer, intent(in) :: n
        
        call fft(x, n, .true.)
    end subroutine ifft
    
    ! Real FFT (optimized for real input)
    subroutine fft_real(x_real, x_imag, n, inverse)
        real(dp), dimension(n), intent(inout) :: x_real
        real(dp), dimension(n), intent(inout) :: x_imag
        integer, intent(in) :: n
        logical, intent(in) :: inverse
        
        complex(dp), dimension(n) :: x_complex
        integer :: i
        
        ! Convert to complex
        do i = 1, n
            x_complex(i) = cmplx(x_real(i), x_imag(i), dp)
        end do
        
        ! Perform FFT
        call fft(x_complex, n, inverse)
        
        ! Extract real and imaginary parts
        do i = 1, n
            x_real(i) = real(x_complex(i), dp)
            x_imag(i) = aimag(x_complex(i))
        end do
    end subroutine fft_real
    
    ! Get next power of 2
    function next_power_of_2(n) result(p)
        integer, intent(in) :: n
        integer :: p
        
        p = 1
        do while (p < n)
            p = p * 2
        end do
        
        ! Ensure we don't exceed maximum FFT size
        if (p > MAX_FFT_SIZE) then
            p = MAX_FFT_SIZE
        end if
    end function next_power_of_2
    
    ! FFT-based convolution
    subroutine fft_convolve(signal, signal_len, ir, ir_len, output, output_len)
        real(dp), dimension(:), intent(in) :: signal
        integer, intent(in) :: signal_len
        real(dp), dimension(:), intent(in) :: ir
        integer, intent(in) :: ir_len
        real(dp), dimension(:), intent(out) :: output
        integer, intent(out) :: output_len
        
        integer :: fft_size, i
        complex(dp), dimension(:), allocatable :: signal_fft, ir_fft, result_fft
        
        ! Calculate required FFT size
        output_len = signal_len + ir_len - 1
        fft_size = next_power_of_2(output_len)
        
        ! Allocate FFT buffers
        allocate(signal_fft(fft_size))
        allocate(ir_fft(fft_size))
        allocate(result_fft(fft_size))
        
        ! Initialize with zeros
        signal_fft = cmplx(0.0_dp, 0.0_dp, dp)
        ir_fft = cmplx(0.0_dp, 0.0_dp, dp)
        
        ! Copy input data
        do i = 1, signal_len
            signal_fft(i) = cmplx(signal(i), 0.0_dp, dp)
        end do
        
        do i = 1, ir_len
            ir_fft(i) = cmplx(ir(i), 0.0_dp, dp)
        end do
        
        ! Forward FFT
        call fft(signal_fft, fft_size, .false.)
        call fft(ir_fft, fft_size, .false.)
        
        ! Frequency domain multiplication
        do i = 1, fft_size
            result_fft(i) = signal_fft(i) * ir_fft(i)
        end do
        
        ! Inverse FFT
        call fft(result_fft, fft_size, .true.)
        
        ! Extract real part of result
        do i = 1, min(output_len, size(output))
            output(i) = real(result_fft(i), dp)
        end do
        
        ! Cleanup
        deallocate(signal_fft)
        deallocate(ir_fft)
        deallocate(result_fft)
        
    end subroutine fft_convolve
    
end module fft_module