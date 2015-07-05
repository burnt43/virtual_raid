#!/usr/local/bin/ruby

DRIVES=10

t = Thread.new {
  loop {
    values = Array.new
    DRIVES.times { values.push Random.rand(16) }
    parity          = values.reduce(:^)
    failure_drive   = Random.rand(DRIVES)
    recovered_value = (values.values_at(*((0..DRIVES-1).to_a.reject {|x| x== failure_drive})).reduce(:^)) ^ parity
    color           = values[failure_drive] == recovered_value ? 32 : 31
    printf("\033[0;%smValues: %s, Parity: %02d - Lost Index #%02d(%02d), Recovered Value: %02d\n\033[0;39m",color,values.collect{|x| sprintf("%02d",x)}.to_s,parity.to_s,failure_drive,values[failure_drive],recovered_value)
    sleep 1 
  }
}
t.join
