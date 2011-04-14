#define FASTADC 1
// defines for setting and clearing register bits, which we use to make the adc take 11us vs 150us; stupid ardunio peeps.

#ifndef cbi
#define cbi(sfr, bit) (_SFR_BYTE(sfr) &= ~_BV(bit))
#endif
#ifndef sbi
#define sbi(sfr, bit) (_SFR_BYTE(sfr) |= _BV(bit))
#endif

//position storage variables
volatile long xpos;
volatile long ypos;
volatile long zpos;

//encoder z-axis state change variable
volatile int zchange;
//toggle variable to generate motor drive square wave
volatile boolean ztoggle;

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
int xdeadlow = 330;
int xdeadhigh = 345;
int xlow = 10;
int xhigh = 506;
float xlowscale = (float(xdeadlow) - float(xlow))/50.0;
float xhighscale = (float(xhigh) - float(xdeadhigh))/50.0;

int ydeadlow = 330;
int ydeadhigh = 345;
int ylow = 10;
int yhigh = 506;
float ylowscale = (float(ydeadlow) - float(ylow))/50.0;
float yhighscale = (float(yhigh) - float(ydeadhigh))/50.0;

//stage translation speed constants for setting up PWM
byte axismoveon; //TCCRnA value to enable motion
byte axismoveoff;//TCCRnA value to disable motion
byte axisfastmove; //TCCRnB value to move fast
byte axisslowmove; //TCCRnB value to move slow

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

  pinMode(xlowlimit, INPUT); 
  pinMode(xhighlimit, INPUT);
  pinMode(ylowlimit, INPUT);
  pinMode(yhighlimit, INPUT);

  // speed up the adc...

#if FASTADC
  // set prescale to 16
  sbi(ADCSRA,ADPS2) ;
  cbi(ADCSRA,ADPS1) ;
  cbi(ADCSRA,ADPS0) ;
#endif

  //TCCRnA - set [7]COMnA1 = 0, [6]COMnA0 = 1, [1]WGMn1 = 0, [0]WGMn0 = 0
  //(COM) - set to toggle OCnA on compare match, (WGM) - set CTC
  axismoveon  = B01000000;
  //TCCRnA - set [7]COMnA1 = 0, [6]COMnA0 = 0, [1]WGMn1 = 0, [0]WGMn0 = 0
  //(COM) - set to diable OCnA toggle, (WGM) - set CTC
  axismoveoff = B00000000;
  TCCR3A = axismoveoff; //disable x axis motion by default
  TCCR4A = axismoveoff; //disable y axis motion by default
  TCCR5A = axismoveoff; //timer 5 set to be just CTC timer, no output

  //TCCRnB - set [4]WGMn3 = 0, [3]WGMn2 = 1, [2]CSn2 = 1, [1]CSn1 = 0, [0]CSn0 = 0
  //(WGM) - set to CTC, (CS) - clock prediv = 256
  //if OCRnx is set to 65535, timer overflows once every ~.95 seconds
  //therefore OCnx pin has a rising edge every ~1.9 seconds
  axisslowmove = B00001100;

  //TCCRnB - set [4]WGMn3 = 0, [3]WGMn2 = 1, [2]CSn2 = 0, [1]CSn1 = 1, [0]CSn0 = 0
  //(WGM) - set to CTC, (CS) - clock prediv = 8
  //if OCRnx is set to 65535, timer overflows ~30.5 times a second
  //therefore OCnx pin has a rising edge ~15.3 times a second  
  axisfastmove = B00001010;

  TCCR3B = axisslowmove; //set Y axis to slow speed by default
  TCCR4B = axisslowmove; //set Y axis to slow speed by default
  
  TCCR5B = B00001011; //gives decent prediv (/64) range for timer clocks  
  
  cli(); //disable interrupts to safely change 16 bit OCRnx values
  OCR5A = 63; //gives approx 2 kHz clock rate
  OCR5B = 6250; //gives approx 20 Hz clock rate
  //renable interrupts
  sei();
  
  //OCRnA values to control PWM rates is set in readjoystick()

  attachInterrupt(0, Aint, CHANGE);
  attachInterrupt(1, Bint, CHANGE);
}

void loop() 
{

}

void readjoystick()
{
  int joyx, joyy, joybuttonpressed;
  int tempxreg, tempyreg;
  unsigned char sreg;

  joyx = analogRead(xjoypin);
  joyy = analogRead(yjoypin);

  scalemovement(&joyx, &joyy);

  //if joystick is in dead zone, stop movement
  if (joyx == 0)
    TCCR3A = axismoveoff;
  else TCCR3A = axismoveon;

  if (joyy ==0)
    TCCR4A = axismoveoff;
  else TCCR4A = axismoveon;

  //set movement direction, stop movement if at limit switches
  if(joyx<0)
  {
    digitalWrite(pinxdir, 0);
    if(digitalRead(xlowlimit) == LOW)
      TCCR3A = axismoveoff;
  }
  else
  {
    digitalWrite(pinxdir, 1);
    if(digitalRead(xhighlimit) == LOW)
      TCCR3A = axismoveoff;
  }

  if(joyy<0)
  {
    digitalWrite(pinydir, 0);
    if(digitalRead(ylowlimit) == LOW)
      TCCR4A = axismoveoff;
  }
  else
  {
    digitalWrite(pinydir, 1);
    if(digitalRead(yhighlimit) == LOW)
      TCCR4A = axismoveoff;
  }

  //convert scaled joystick data to PWM control register data
  tempxreg = scalePWM(joyx);
  tempyreg = scalePWM(joyy);

  //disable interrputs and update the OCRnA registers to adjust PWM speed
  cli();
  OCR3A = tempxreg;
  OCR4A = tempyreg;
  //renable interrupts
  sei();

  joybuttonpressed = digitalRead(joybuttonpin);

  if(joybuttonpressed == 0)
  {
    TCCR3B = axisslowmove;
    TCCR4B = axisslowmove;
  }
  else 
  {
    TCCR3B = axisfastmove;
    TCCR4B = axisfastmove;
  }
}

void scalemovement(int *joyx, int *joyy)
{ //arbitrary mapping of joystick input values to ranked value ranks
  if(*joyx < xdeadlow)
  {
    *joyx -= xdeadlow;
    *joyx /= xlowscale;
  }  
  if((*joyx > xdeadlow)&&(*joyx < xdeadhigh))
    *joyx = 0;
  if(*joyx > xdeadhigh)
  {
    *joyx -= xdeadhigh;
    *joyx /= xhighscale;
  }

  if(*joyy < ydeadlow)
  {
    *joyy -= ydeadlow;
    *joyy /= ylowscale;
  }  
  if((*joyy > ydeadlow)&&(*joyy < ydeadhigh))
    *joyy = 0;
  if(*joyy > ydeadhigh)
  {
    *joyy -= ydeadhigh;
    *joyy /= yhighscale;
  }
}

int scalePWM(int rank)
{
  return 32768/abs(rank);
}

ISR(TIM3_COMPA)
{ //x-axis tally
  if(PINE3) //if x-step has gone high
  {
    if(PING5) //increment or decrement x counter depending on step direction
      xpos++;
    else
      xpos--;
  }
}

ISR(TIM4_COMPA)
{ //y-axis tally
  if(PINH3) //if y-step has gone high
  {
    if(PINH4) //increment or decrement y counter depending on step direction
      ypos++;
    else
      ypos--;
  }
}

ISR(TIM5_COMPA)
{ //fast-tick timer, 2 kHz
  if(ztoggle == 0)
  {
    ztoggle = 1;
    if(zchange >= 0)
    { //if + z movement is queued up, move up, keep track of movement
      zchange --;
      zpos ++;
      //set E4 dir line to go up
      //rising edge to step line E5
      PORTE = PORTE|B00110000;
    }
    if(zchange <= 0)
    { //if -z movement queued up, move down, keep track of movement
      zchange ++;
      zpos --;
      PORTE = PORTE|B00100000;  //rising edge to step line E5
      PORTE = PORTE&B11101111; //set E4 dir line to go down
    }
  }
  if(ztoggle == 1) 
  {
    PORTE = PORTE&B11011111; //falling edge to step line E5
  }
}

ISR(TIM5_COMPB)
{ //slow-tick timer, 20 Hz

}

void Aint()
{
  boolean Atemp; //temp variable to hold value for rotary encoder A line
  boolean Btemp; //blahblah
  boolean zstep; //encoder switch position determines number of motor steps
  //as rot encoder moves clockwise, values go 0->1->3->2->0...
  //PIND1 - Int1 - dig pin 20, PIND0 - Int0 - dig pin 21
  Atemp = PIND0;
  Btemp = PIND1;

  if(PIND2 == 1) zstep = 1; //if encoder is pushed in, do 10x steps
  else zstep = 10;

  if(Atemp == 0)
  {
    if(Btemp == 0) zchange += zstep;
    else zchange -= zstep;
  }
  else
  {
    if(Btemp == 1) zchange += zstep;
    else zchange -= zstep;
  }
}

void Bint()
{
  boolean Atemp; //temp variable to hold value for rotary encoder A line
  boolean Btemp; //blahblah
  boolean zstep; //encoder switch position determines number of motor steps
  //as rot encoder moves clockwise, values go 0->1->3->2->0...
  //PIND1 - Int1 - dig pin 20, PIND0 - Int0 - dig pin 21
  Atemp = PIND0;
  Btemp = PIND1;

  if(PIND2 == 1) zstep = 1; //if encoder is pushed in, do 10x steps
  else zstep = 10;

  if(Btemp == 0)
  {
    if(Atemp == 1) zchange += zstep;
    else zchange -= zstep;
  }
  else
  {
    if(Atemp == 1) zchange += zstep;
    else zchange -= zstep;
  }
}


