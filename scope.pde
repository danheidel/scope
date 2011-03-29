#define FASTADC 1

// defines for setting and clearing register bits, which we use to make the adc take 11us vs 150us; stupid ardunio peeps.

#ifndef cbi
#define cbi(sfr, bit) (_SFR_BYTE(sfr) &= ~_BV(bit))
#endif
#ifndef sbi
#define sbi(sfr, bit) (_SFR_BYTE(sfr) |= _BV(bit))
#endif

//pin assignments
//joystick x
int xjoypin = 0;//analog 0
//joystick y
int yjoypin = 1;//analog 1
//joystick button
int joybuttonpin = 56;//analog pin 2

//z encoder output A
int zencpinA = 21;//external int0
//z encoder output B
int zencpinB = 20;//external int1
// z encoder push button
int zencsw = 19;

int preset1 = 8;
int preset1led = 9; //PWM T2B
int preset2 = 10;
int preset2led = 11; //PWM T1A
int preset3 = 12;
int preset3led = 13; //PWN T0A
//note, these picked to not use timers 3&4 since those are being used and
//altered by the X/Y drive functions

int pushsw = 18;
int togglesw = -1;

int pinxdir=4;
int pinxstep=5;//PWM T3A

int pinystep=6;//PWM T4A
int pinydir=7;

int pinzdir=2; //no PWM here, triggered solely via interrupt
int pinzstep=3;

int xlowlimit = 14;
int xhighlimit = 15;

int ylowlimit = 16;
int yhighlimit = 17;

//Joystick calibration values
int ydeadlow = 330;
int ydeadhigh = 345;
int ylow = 10;
int yhigh = 506;

int xdeadlow = 330;
int xdeadhigh = 345;
int xlow = 10;
int xhigh = 506;

//stage translation speed constants
int xslowprescale = 128; //clock divider for PWM in slow translation mode
int xfastprescale = 4; //clock divider for PWM in fast translation mode
int yslowprescale = 128; //clock divider for PWN in slow translation mode
int yfastprescale = 4; //clock divider for PWM in fast translation mode

void setup() {
  Serial.begin(115200); // for debug?
  
  // setup io lines...
  pinMode(xjoypin, INPUT);
  pinMode(yjoypin, INPUT);
  pinMode(joybuttonpin, INPUT);
  digitalWrite(joybuttonpin, HIGH); //enable pullup resistor
  
  pinMode(zencpinA, INPUT);
  digitalWrite(zencpinA, HIGH); //enable pullup resistor
  pinMode(zencpinB, INPUT);
  digitalWrite(zencpinB, HIGH); //enable pullup resistor
  pinMode(zencsw, INPUT);
  digitalWrite(zencsw, HIGH); //enable pullup resistor
  
  pinMode(preset1, INPUT);
  digitalWrite(preset1, HIGH); //enable pullup resistor
  pinMode(preset1led, OUTPUT);
  pinMode(preset2, INPUT);
  digitalWrite(preset2, HIGH); //enable pullup resistor
  pinMode(preset2led, OUTPUT);
  pinMode(preset3, INPUT);
  digitalWrite(preset3, HIGH); //enablepullup resistor
  pinMode(preset3led, OUTPUT);
  
  pinMode(pushsw, INPUT);
  digitalWrite(pushsw, HIGH); //enable pullup resistor
  
  pinMode(pinxdir, OUTPUT);
  pinMode(pinxstep, OUTPUT);//PWM T3A

  pinMode(pinystep, OUTPUT);//PWM T4A
  pinMode(pinydir, OUTPUT);

  pinMode(pinzdir, OUTPUT); //no PWM here, triggered solely via interrupt
  pinMode(pinzstep, OUTPUT);

  // speed up the adc...

  #if FASTADC
    // set prescale to 16
    sbi(ADCSRA,ADPS2) ;
    cbi(ADCSRA,ADPS1) ;
    cbi(ADCSRA,ADPS0) ;
  #endif
}

void loop() {
  unsigned long mainloopstartime = micros();
  unsigned long debugtiming = micros();  // todo: move these up above? do they get set each main loop or what? 


  // replace these two with spi calls to ian... 
  
  if (xjoycal > 2) {
    if (xdelay < mainloopstartime - xdelay_last) {
      xdelay_last = mainloopstartime;
      //pulse the line...
      digitalWrite(pinxstep, 1^digitalRead(pinxstep));
      digitalWrite(pinxdir,xjoydir);
      if (xjoydir == 1) {
         xsteps++;
      } else { 
        xsteps--; 
      }
    }
  }

  if (yjoycal > 2) {
    if (ydelay < mainloopstartime - ydelay_last) {
      ydelay_last = mainloopstartime;
      //pulse the line...
      digitalWrite(pinystep, 1^digitalRead(pinystep));
      digitalWrite(pinydir,yjoydir);
      if (yjoydir == 1) {
         ysteps++;
      } else { 
        ysteps--; 
      }
    }
  }
           
  if (serial_update < mainloopstartime - serial_update_last) {
    serial_update_last = mainloopstartime;
    tweet(); // takes 256 us
  }  
  else if (screendata_update < mainloopstartime - screendata_update_last) {
    screendata_update_last = mainloopstartime;
    twitter(); // takes 300? us
  }  

  else if (analog_read < mainloopstartime - analog_read_last) {
    analog_read_last = mainloopstartime;
    readjoydata(); // takes under 256 us.
    calcstepperdelay();
  }
  

    if ((micros() - debugtiming) > debugmaxtime) { debugmaxtime = micros() - debugtiming;}
  
}

// joycal functions
int readjoydata () {
  xjoycal = readjoy(&xjoypin);
  yjoycal = readjoy(&yjoypin);
  joybuttonstate = readbutton(&joybuttonpin);
  if (xjoycal < 0) { 
    xjoycal = xjoycal * -1;
    xjoydir = 0;
  } else { xjoydir = 1; }

  if (yjoycal < 0) { 
    yjoycal = yjoycal * -1;
    yjoydir = 0;
  } else { yjoydir = 1; }
  
  
}

int calcstepperdelay() {
  
  xdelay = long((100-long(xjoycal)) * 900);
  ydelay = long((100-long(yjoycal)) * 900);

  if (xdelay < xmindelay) { xdelay = xmindelay; }
  if (xdelay > xmaxdelay) { xdelay = xmaxdelay; }

  if (ydelay < ymindelay) { ydelay = ymindelay; }
  if (ydelay > ymaxdelay) { ydelay = ymaxdelay; }
  
  return true;
}

int readbutton(int *mypin) {
  return digitalRead(*mypin);
}

int readjoy (int *mypin) {
  int rawvalue = analogRead(*mypin);
  rawvalue = int((rawvalue-500)/5);
  
  if (rawvalue > 97) { rawvalue=100; }
  if (rawvalue < -97) { rawvalue=-100; }
  return (rawvalue);
  }

int tweet () {
  Serial.print(screendata[screendatapos]);
  screendatapos++;
  if (screendatapos > 79) { screendatapos = 0; } 
}

int twitter () {

  sprintf(screentempbuffer,"X: %03d Y: %03d B:%d",xjoycal,yjoycal,joybuttonstate); // takes 200us!
  strncpy(screendata+20, screentempbuffer, 17); // takes 16us

  sprintf(screentempbuffer,"%05d",debugmaxtime);
  strncpy(screendata, screentempbuffer,5);

  sprintf(screentempbuffer,"Ys:%06d Xs:%06d",ysteps, xsteps);
  strncpy(screendata+40, screentempbuffer, 20); // takes 16us

//  sprintf(screentempbuffer,"Xd:%06ld Yd:%06ld ",xdelay,ydelay); // takes 200us!
//  strncpy(screendata+60, screentempbuffer, 20); // takes 16us
  return true;  
}
