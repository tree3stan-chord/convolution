! constants.f90
! Shared constants for the convolution reverb engine

module constants
    implicit none
    
    ! Precision parameters
    integer, parameter :: sp = kind(1.0)     ! Single precision
    integer, parameter :: dp = kind(1.0d0)   ! Double precision
    
    ! Mathematical constants
    real(dp), parameter :: pi = 3.14159265358979323846_dp
    real(dp), parameter :: two_pi = 2.0_dp * pi
    real(dp), parameter :: half_pi = pi / 2.0_dp
    
    ! Audio processing constants
    integer, parameter :: MAX_BUFFER_SIZE = 192000   ! 4 seconds at 48kHz
    integer, parameter :: MAX_IR_SIZE = 96000        ! 2 seconds at 48kHz
    integer, parameter :: MAX_CHANNELS = 2           ! Stereo support
    integer, parameter :: DEFAULT_SAMPLE_RATE = 48000
    
    ! FFT constants
    integer, parameter :: MIN_FFT_SIZE = 64
    integer, parameter :: MAX_FFT_SIZE = 65536
    
    ! Reverb parameters ranges
    real(dp), parameter :: MIN_ROOM_SIZE = 0.0_dp
    real(dp), parameter :: MAX_ROOM_SIZE = 100.0_dp
    real(dp), parameter :: MIN_DECAY_TIME = 0.1_dp
    real(dp), parameter :: MAX_DECAY_TIME = 10.0_dp
    real(dp), parameter :: MIN_PRE_DELAY = 0.0_dp
    real(dp), parameter :: MAX_PRE_DELAY = 100.0_dp
    real(dp), parameter :: MIN_DAMPING = 0.0_dp
    real(dp), parameter :: MAX_DAMPING = 100.0_dp
    
    ! Processing block size for efficiency
    integer, parameter :: BLOCK_SIZE = 128
    
    ! Impulse response types
    integer, parameter :: IR_TYPE_HALL = 1
    integer, parameter :: IR_TYPE_CATHEDRAL = 2
    integer, parameter :: IR_TYPE_ROOM = 3
    integer, parameter :: IR_TYPE_PLATE = 4
    integer, parameter :: IR_TYPE_SPRING = 5
    
    ! Error codes
    integer, parameter :: SUCCESS = 0
    integer, parameter :: ERROR_INVALID_PARAMETER = -1
    integer, parameter :: ERROR_BUFFER_OVERFLOW = -2
    integer, parameter :: ERROR_NOT_INITIALIZED = -3
    
end module constants