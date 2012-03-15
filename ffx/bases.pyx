import numpy, scipy
cimport numpy
cimport cython

#GTH = Greater-Than Hinge function, LTH = Less-Than Hinge function
cdef enum BasisFunc:
    OP_ABS = 1
    OP_MAX0 = 2
    OP_MIN0 = 3
    OP_LOG10 = 4
    OP_GTH = 5
    OP_LTH = 6


cdef extern from "math.h":
    bint isnan(double x)


cpdef coefStr(double x):
    """Gracefully print a number to 3 significant digits.  See _testCoefStr in unit tests"""
    if x == 0.0:        s = '0'
    elif numpy.abs(x) < 1e-4: s = ('%.2e' % x).replace('e-0', 'e-')
    elif numpy.abs(x) < 1e-3: s = '%.6f' % x
    elif numpy.abs(x) < 1e-2: s = '%.5f' % x
    elif numpy.abs(x) < 1e-1: s = '%.4f' % x
    elif numpy.abs(x) < 1e0:  s = '%.3f' % x
    elif numpy.abs(x) < 1e1:  s = '%.2f' % x
    elif numpy.abs(x) < 1e2:  s = '%.1f' % x
    elif numpy.abs(x) < 1e4:  s = '%.0f' % x
    else:                     s = ('%.2e' % x).replace('e+0', 'e')
    return s


cdef class SimpleBase:
    """e.g. x4^2"""

    cdef double var
    cdef public double exponent

    def __cinit__(self, double var, double exponent):
        self.var = var
        self.exponent = exponent

    def simulate(self, X):
        """
        @arguments
          X -- 2d array of [sample_i][var_i] : float
        @return
          y -- 1d array of [sample_i] : float
        """
        return numpy.power(X[:,self.var], self.exponent)

    def __str__(self):
        if self.exponent == 1:
            return 'x%d' % self.var
        else:
            return 'x%d^%g' % (self.var, self.exponent)
                                
cdef class OperatorBase:
    """e.g. log(x4^2)"""
    
    cdef BasisFunc nonlin_op
    cdef SimpleBase simple_base
    cdef public double thr

    def __cinit__(self, SimpleBase simple_base, 
                        BasisFunc  nonlin_op, 
                        double     thr):
        """
        @arguments
          simple_base -- SimpleBase
          nonlin_op -- one of OPS
          thr -- None or float -- depends on nonlin_op
        """
        self.simple_base = simple_base
        self.nonlin_op   = nonlin_op
        self.thr         = thr

    cpdef simulate(self, X):
        """
        @arguments
          X -- 2d array of [sample_i][var_i] : float
        @return
          y -- 1d array of [sample_i] : float
        """
        op = self.nonlin_op
        ok = True
        y_lin = self.simple_base.simulate(X)

        if   op == OP_ABS:   ya = numpy.abs(y_lin)
        elif op == OP_MAX0:  ya = numpy.clip(y_lin, 0.0, numpy.Inf)
        elif op == OP_MIN0:  ya = numpy.clip(y_lin, -numpy.Inf, 0.0)
        elif op == OP_LOG10:
            #safeguard against: log() on values <= 0.0
            mn, mx = min(y_lin), max(y_lin)
            if mn <= 0.0 or isnan(mn) or mx == numpy.Inf or isnan(mx):
                ok = False
            else:
                ya = numpy.log10(y_lin)
        elif op == OP_GTH:   ya = numpy.clip(self.thr - y_lin, 0.0, numpy.Inf)
        elif op == OP_LTH:   ya = numpy.clip(y_lin - self.thr, 0.0, numpy.Inf)
        else:                raise 'Unknown op %d' % op

        if ok: #could always do ** exp, but faster ways if exp is 0,1
            y = ya
        else:
            y = numpy.Inf * numpy.ones(X.shape[0], dtype=float)    
        return y
    
    def __str__(self):
        op = self.nonlin_op
        simple_s = str(self.simple_base)
        if op == OP_ABS:     return 'abs(%s)' % simple_s
        elif op == OP_MAX0:  return 'max(0, %s)' % simple_s
        elif op == OP_MIN0:  return 'min(0, %s)' % simple_s
        elif op == OP_LOG10: return 'log10(%s)' % simple_s
        elif op == OP_GTH:   return ('max(0,%s-%s)' % (simple_s, coefStr(self.thr))).replace('--','+')
        elif op == OP_LTH:   return 'max(0,%s-%s)' % (coefStr(self.thr), simple_s)
        else:                raise 'Unknown op %d' % op


cdef class ProductBase:
    cdef public base1
    cdef public base2

    """e.g. x2^2 * log(x1^3)"""
    def __cinit__(self, base1, base2):
        self.base1 = base1
        self.base2 = base2

    def simulate(self, X):
        """
        @arguments
          X -- 2d array of [sample_i][var_i] : float
        @return
          y -- 1d array of [sample_i] : float
        """
        yhat1 = self.base1.simulate(X)
        yhat2 = self.base2.simulate(X)
        return yhat1 * yhat2

    def __str__(self):
        return '%s * %s' % (self.base1, self.base2)


cdef class ConstantModel:
    """e.g. 3.2"""

    cdef double constant
    cdef int numvars
    cdef public double test_nmse

    def __cinit__(self, double constant, int numvars):
        """
        @description        
            Constructor.
    
        @arguments        
            constant -- float -- constant value returned by this model
            numvars -- int -- number of input variables to this model
        """ 
        self.constant = constant 
        self.numvars  = numvars

    cpdef int numBases(self):
        """Return total number of bases"""
        return 0

    cpdef numpy.ndarray[double, ndim=1] simulate(self, X):
        """
        @arguments
          X -- 2d array of [sample_i][var_i] : float
        @return
          y -- 1d array of [sample_i] : float
        """
        cdef unsigned int N = X.shape[0]
        cdef numpy.ndarray[double, ndim=1] yhat

        if isnan(self.constant): #corner case
            yhat = numpy.array([numpy.Inf] * N)
        else: #typical case
            yhat = numpy.ones(N, dtype=float) * self.constant  
        return yhat
    
    def __str__(self):
        return self.str2()

    def str2(self, *args):
        return coefStr(self.constant)




